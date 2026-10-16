use serde_json::{json, Value};
use std::io::{self, BufRead};
use std::ops::Bound;
use yrs::types::{Attrs, ToJson};
use yrs::updates::decoder::Decode;
use yrs::{
    Array, ArrayRef, ClientID, Doc, GetString, Map, MapRef, OffsetKind, Options, Out, Quotable,
    ReadTxn, StateVector, Text, TextRef, Transact, Update, WeakRef, XmlTextRef,
};
fn n(v: &Value) -> u32 {
    v.as_u64().unwrap() as u32
}
fn bound(v: &Value, len: u32) -> Bound<u32> {
    if v.is_null() {
        Bound::Unbounded
    } else if v[0] == "i" {
        Bound::Included(n(&v[1]) % len)
    } else {
        Bound::Excluded(n(&v[1]) % len)
    }
}
fn report(d: &Doc, v2: bool) -> Value {
    let text = d.get_or_insert_text("text");
    let array = d.get_or_insert_array("array");
    let map = d.get_or_insert_map("map");
    let links = d.get_or_insert_map("links");
    let txn = d.transact();
    let mut result = serde_json::Map::new();
    for (key, value) in links.iter(&txn) {
        if let Out::YWeakLink(link) = value {
            let ids = json!([
                link.start_id()
                    .map(|id| json!([id.client.get().to_string(), id.clock])),
                link.end_id()
                    .map(|id| json!([id.client.get().to_string(), id.clock]))
            ]);
            let value = if key.starts_with('t') {
                let l: WeakRef<TextRef> = link.clone().into();
                let x: WeakRef<XmlTextRef> = link.into();
                {
                    let xml = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        x.get_string(&txn)
                    }));
                    let xml = match xml {
                        Ok(s) => json!(s),
                        Err(e) => {
                            let msg = e
                                .downcast_ref::<String>()
                                .cloned()
                                .or_else(|| e.downcast_ref::<&str>().map(|s| s.to_string()))
                                .unwrap_or_default();
                            assert!(
                                msg.contains("out of bounds for string")
                                    || msg.contains("not a char boundary"),
                                "unexpected panic: {}",
                                msg
                            );
                            json!({"upstream_xml_panic":msg})
                        }
                    };
                    json!([l.get_string(&txn), xml])
                }
            } else if key.starts_with('a') {
                let l: WeakRef<ArrayRef> = link.into();
                json!(l.unquote(&txn).map(|v| v.to_json(&txn)).collect::<Vec<_>>())
            } else {
                let l: WeakRef<MapRef> = link.into();
                json!(l.try_deref_value(&txn).map(|v| v.to_json(&txn)))
            };
            result.insert(key.into(), json!([ids, value]));
        }
    }
    let mut state: Vec<_> = txn.state_vector().iter().map(|(c,n)|(c.get(),*n)).collect(); state.sort();
    json!({"state":state,"text":text.get_string(&txn),"array":array.to_json(&txn),"map":map.to_json(&txn),"links":result,"wire":if v2{txn.encode_state_as_update_v2(&StateVector::default())}else{txn.encode_state_as_update_v1(&StateVector::default())}})
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let v2 = args.iter().any(|a| a == "v2");
    let gc = args.iter().any(|a| a == "gc");
    let raw_bounds = args.iter().any(|a| a == "raw-bounds");
    for line in io::stdin().lock().lines() {
        let input: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let d = Doc::with_options(Options {
            client_id: ClientID::new(if input[0][0] == "client" { input[0][1].as_u64().unwrap() } else { 1 }),
            offset_kind: OffsetKind::Utf16,
            skip_gc: !gc,
            cleanup_formatting: true,
            ..Options::default()
        });
        let t = d.get_or_insert_text("text");
        let a = d.get_or_insert_array("array");
        let m = d.get_or_insert_map("map");
        let links = d.get_or_insert_map("links");
        let mut rows = vec![];
        let events = std::sync::Arc::new(std::sync::Mutex::new(Vec::<String>::new()));
        for op in input.as_array().unwrap() {
            match op[0].as_str().unwrap() {
                "client" => {},
                "i" => {
                    let mut txn = d.transact_mut();
                    let len = t.len(&txn);
                    t.insert(&mut txn, n(&op[1]) % (len + 1), op[2].as_str().unwrap());
                }
                "d" => {
                    let mut txn = d.transact_mut();
                    let len = t.len(&txn);
                    if len > 0 {
                        let i = n(&op[1]) % len;
                        t.remove_range(&mut txn, i, n(&op[2]).min(len - i));
                    }
                }
                "f" => {
                    let mut txn = d.transact_mut();
                    let len = t.len(&txn);
                    if len > 0 {
                        let i = n(&op[1]) % len;
                        t.format(
                            &mut txn,
                            i,
                            n(&op[2]).min(len - i),
                            Attrs::from([(
                                "b".into(),
                                op[3]
                                    .as_bool()
                                    .map(yrs::Any::Bool)
                                    .unwrap_or(yrs::Any::Null),
                            )]),
                        );
                    }
                }
                "ai" => {
                    let mut txn = d.transact_mut();
                    let len = a.len(&txn);
                    a.insert(&mut txn, n(&op[1]) % (len + 1), n(&op[2]) as i32);
                }
                "ad" => {
                    let mut txn = d.transact_mut();
                    let len = a.len(&txn);
                    if len > 0 {
                        let i = n(&op[1]) % len;
                        a.remove_range(&mut txn, i, n(&op[2]).min(len - i));
                    }
                }
                "m" => {
                    m.insert(
                        &mut d.transact_mut(),
                        op[1].as_str().unwrap(),
                        n(&op[2]) as i32,
                    );
                }
                "md" => {
                    m.remove(&mut d.transact_mut(), op[1].as_str().unwrap());
                }
                "ml" => {
                    let mut txn = d.transact_mut();
                    if let Some(p) = m.link(&txn, op[2].as_str().unwrap()) {
                        links.insert(&mut txn, op[1].as_str().unwrap(), p);
                    }
                }
                "q" => {
                    let key = op[1].as_str().unwrap();
                    let mut txn = d.transact_mut();
                    let len = if key.starts_with('t') {
                        t.len(&txn)
                    } else {
                        a.len(&txn)
                    };
                    if len > 0 {
                        let mut lo = bound(&op[2], len);
                        let mut hi = bound(&op[3], len);
                        let val = |b: &Bound<u32>| match b {
                            Bound::Included(n) | Bound::Excluded(n) => *n,
                            Bound::Unbounded => 0,
                        };
                        if !matches!(lo, Bound::Unbounded)
                            && !matches!(hi, Bound::Unbounded)
                            && val(&lo) > val(&hi)
                        {
                            std::mem::swap(&mut lo, &mut hi)
                        };
                        if !raw_bounds
                            && !matches!(lo, Bound::Unbounded)
                            && !matches!(hi, Bound::Unbounded)
                            && val(&lo) == val(&hi)
                        {
                            lo = Bound::Included(val(&lo));
                            hi = lo.clone();
                        };
                        if key.starts_with('t') {
                            let p = t.quote(&txn, (lo, hi)).unwrap();
                            links.insert(&mut txn, key, p);
                        } else {
                            let p = a.quote(&txn, (lo, hi)).unwrap();
                            links.insert(&mut txn, key, p);
                        }
                    }
                }
                "del" => {
                    links.remove(&mut d.transact_mut(), op[1].as_str().unwrap());
                }
                "load" => {
                    let bytes: Vec<u8> = serde_json::from_value(op[1].clone()).unwrap();
                    d.transact_mut()
                        .apply_update(if v2 {
                            Update::decode_v2(&bytes).unwrap()
                        } else {
                            Update::decode_v1(&bytes).unwrap()
                        })
                        .unwrap();
                }
                _ => panic!("op"),
            };
            let mut row = report(&d, v2);
            row["events"] = json!(std::mem::take(&mut *events.lock().unwrap()));
            rows.push(row);
            {
                let txn = d.transact();
                for (key, value) in links.iter(&txn) {
                    if let Out::YWeakLink(link) = value {
                        let log = events.clone();
                        let key = key.to_string();
                        yrs::Observable::observe(&link, "watch", move |_, _| {
                            log.lock().unwrap().push(key.clone())
                        });
                    }
                }
            }
        }
        println!("{}", json!(rows));
    }
}
