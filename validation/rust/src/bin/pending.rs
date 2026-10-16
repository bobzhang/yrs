use serde_json::{json, Value};
use std::io::{self, BufRead};
use yrs::updates::{
    decoder::Decode,
    encoder::{Encode, Encoder},
};
use yrs::{
    ClientID, Doc, GetString, IdSet, Options, ReadTxn, StateVector, Text, Transact, Update,
    WriteTxn, ID,
};
fn state(s: StateVector) -> Value {
    let mut pairs = s.iter().map(|(c, n)| (c.get(), *n)).collect::<Vec<_>>();
    pairs.sort();
    json!(pairs)
}
fn info(u: Update) -> Value {
    let ranges = |s: IdSet| {
        s.iter()
            .flat_map(|(c, rs)| rs.iter().map(move |r| (c.get(), r.start, r.end)))
            .collect::<Vec<_>>()
    };
    json!({"state":state(u.state_vector()),"lower":state(u.state_vector_lower()),"deleted":ranges(u.delete_set().clone()),"inserted":ranges(u.insertions(true)),"empty":u.is_empty()})
}
fn main() {
    for line in io::stdin().lock().lines() {
        let input: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let d = Doc::with_options(Options {
            client_id: ClientID::new(1),
            skip_gc: true,
            ..Options::default()
        });
        if let Some(seed) = input["produce"].as_u64() {
            let text = d.get_or_insert_text("text");
            let mut packets = vec![];
            let mut seed = seed + 1;
            for i in 0..48 {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                let mut tx = d.transact_mut();
                let len = text.len(&tx);
                if i % 3 != 2 || len == 0 {
                    text.insert(&mut tx, (seed % (len as u64 + 1)) as u32, "abc")
                } else {
                    let at = (seed % len as u64) as u32;
                    text.remove_range(&mut tx, at, (1 + (seed % 5) as u32).min(len - at));
                }
                packets.push(tx.encode_update_v1());
            }
            println!("{}", json!(packets));
            continue;
        }
        for packet in input["packets"].as_array().unwrap() {
            let bytes: Vec<u8> = serde_json::from_value(packet.clone()).unwrap();
            d.transact_mut()
                .apply_update(Update::decode_v1(&bytes).unwrap())
                .unwrap();
        }
        if let Some(scope) = input.get("gc") {
            let mut set = IdSet::new();
            for r in scope.as_array().unwrap() {
                set.insert(
                    ID::new(
                        ClientID::new(r[0].as_u64().unwrap()),
                        r[1].as_u64().unwrap() as u32,
                    ),
                    r[2].as_u64().unwrap() as u32,
                );
            }
            d.transact_mut().gc(Some(&set));
        }
        let view = |doc: &Doc| {
            let tx = doc.transact();
            let retained = if input.get("gc").is_some() {
                let mut encoder = yrs::updates::encoder::EncoderV1::new();
                tx.encode_state_from_snapshot(
                    &yrs::Snapshot::new(tx.state_vector(), IdSet::new()),
                    &mut encoder,
                )
                .unwrap();
                let peer = Doc::with_client_id(99);
                peer.transact_mut()
                    .apply_update(Update::decode_v1(&encoder.to_vec()).unwrap())
                    .unwrap();
                let t = peer.get_or_insert_text("text");
                let value = t.get_string(&peer.transact());
                json!(value)
            } else {
                Value::Null
            };
            json!({"retained":retained,"missing":tx.has_missing_updates(),"state":state(tx.state_vector()),"text":tx.get_text("text").map(|t|t.get_string(&tx)),"full":info(Update::decode_v1(&tx.encode_state_as_update_v1(&StateVector::default())).unwrap()),"diff":info(Update::decode_v1(&tx.encode_diff_v1(&StateVector::default())).unwrap()),"wire":tx.encode_diff_v1(&StateVector::default())})
        };
        if input["replay_original"].as_bool() == Some(true) {
            // Resolve the same original packets to a fixed point without using
            // Yrs's merged pending store. Drop unready blocks before each packet;
            // every original packet is offered again on the following pass.
            let replay = Doc::with_options(Options {
                client_id: ClientID::new(2),
                skip_gc: true,
                ..Options::default()
            });
            let mut rounds = 0;
            loop {
                let prior = replay.transact().encode_diff_v1(&StateVector::default());
                for packet in input["packets"].as_array().unwrap() {
                    let bytes: Vec<u8> = serde_json::from_value(packet.clone()).unwrap();
                    let mut tx = replay.transact_mut();
                    tx.prune_pending();
                    tx.apply_update(Update::decode_v1(&bytes).unwrap()).unwrap();
                }
                replay.transact_mut().prune_pending();
                rounds += 1;
                let current = replay.transact().encode_diff_v1(&StateVector::default());
                if current == prior {
                    break;
                }
                assert!(rounds <= 49, "original packet replay failed to settle");
            }
            println!(
                "{}",
                json!({"replayed_original":view(&replay),"rounds":rounds})
            );
            continue;
        }
        let before = view(&d);
        let pending = d.transact_mut().prune_pending();
        let saved = pending.as_ref().map(|u| u.encode_v1());
        let pending = pending.map(info);
        let after = view(&d);
        if let Some(p) = saved {
            d.transact_mut()
                .apply_update(Update::decode_v1(&p).unwrap())
                .unwrap();
        }
        let restored = view(&d);
        let mut retry_rounds = 0;
        for _ in 0..48 {
            let prior = d.transact().encode_diff_v1(&StateVector::default());
            let pending = d.transact_mut().prune_pending();
            if let Some(p) = pending {
                d.transact_mut().apply_update(p).unwrap();
            } else {
                break;
            }
            let current = d.transact().encode_diff_v1(&StateVector::default());
            if current == prior {
                break;
            }
            retry_rounds += 1;
        }
        let settled = view(&d);
        if let Some(packets) = input["complete"].as_array() {
            for packet in packets {
                let bytes: Vec<u8> = serde_json::from_value(packet.clone()).unwrap();
                d.transact_mut()
                    .apply_update(Update::decode_v1(&bytes).unwrap())
                    .unwrap();
            }
        }
        let completed = view(&d);
        println!(
            "{}",
            json!({"before":before,"pending":pending,"after":after,"restored":restored,"settled":settled,"completed":completed,"retry_rounds":retry_rounds})
        );
    }
}
