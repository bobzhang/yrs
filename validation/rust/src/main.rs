use std::io::{self, BufRead};
use yrs::{Doc, Text, GetString, ReadTxn, Transact, Options, OffsetKind, Update};
use yrs::updates::decoder::Decode;
use yrs::{Array, Map};
use yrs::types::ToJson;
use serde_json::{Value, json};
fn hex(b: &[u8]) -> String { b.iter().map(|b| format!("{b:02x}")).collect() }
fn unhex(s: &str) -> Vec<u8> { (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i+2],16).unwrap()).collect() }
fn main() {
 let v2=std::env::args().any(|s|s=="v2");
 let gc=std::env::args().any(|s|s=="--gc");
 for line in io::stdin().lock().lines() {
  let commands: Vec<Value> = serde_json::from_str(&line.unwrap()).unwrap();
  let docs: Vec<Doc> = (1..=3).map(|i| { let mut o=Options::with_client_id(yrs::block::ClientID::new(i)); o.offset_kind=OffsetKind::Utf16; o.skip_gc=!gc; Doc::with_options(o) }).collect();
  let texts: Vec<_> = docs.iter().map(|d| d.get_or_insert_text("note")).collect();
  let arrays: Vec<_> = docs.iter().map(|d| d.get_or_insert_array("items")).collect();
  let maps: Vec<_> = docs.iter().map(|d| d.get_or_insert_map("settings")).collect();
  let mut queued: Vec<(usize,Vec<u8>)> = vec![];
  let mut snapshots=vec![];
  let mut trace=false;
  let mut history=vec![];
  let mut local_cases=vec![];
  let mut previous=vec![yrs::StateVector::default();3];
  for cmd in commands {
   let a=cmd.as_array().unwrap();
   let kind=a[0].as_str().unwrap();
   let x=a[1].as_u64().unwrap() as usize;
   if ["i","d","f","t","b"].contains(&kind) && trace {
    let bytes=if v2 { docs[x].transact().encode_state_as_update_v2(&Default::default()) } else { docs[x].transact().encode_state_as_update_v1(&Default::default()) };
    local_cases.push(json!([["a",x,hex(&bytes)],cmd.clone()]));
   }
   match kind {
    "trace" => { trace=true; continue; }
    "i" => { let mut txn=docs[x].transact_mut(); let n=texts[x].len(&txn); let pos=a[2].as_u64().unwrap() as u32 % (n+1); texts[x].insert(&mut txn,pos,a[3].as_str().unwrap()); }
    "d" => { let mut txn=docs[x].transact_mut(); let n=texts[x].len(&txn); let pos=a[2].as_u64().unwrap() as u32 % (n+1); let len=a[3].as_u64().unwrap() as u32 % (n-pos+1); texts[x].remove_range(&mut txn,pos,len); }
    "f" | "t" | "b" => {
      let mut txn=docs[x].transact_mut();
      let n=texts[x].len(&txn); let pos=a[2].as_u64().unwrap() as u32 % (n+1);
      let attrs: yrs::types::Attrs=serde_json::from_value(a[4].clone()).unwrap();
      if kind=="f" { let len=a[3].as_u64().unwrap() as u32 % (n-pos+1); texts[x].format(&mut txn,pos,len,attrs); }
      else if kind=="t" { texts[x].insert_with_attributes(&mut txn,pos,a[3].as_str().unwrap(),attrs); }
      else { let value: yrs::Any=serde_json::from_value(a[3].clone()).unwrap(); texts[x].insert_embed_with_attributes(&mut txn,pos,value,attrs); }
    }
    "n" => {
      let mut txn=docs[x].transact_mut();
      let inner=maps[x].insert(&mut txn,a[2].as_str().unwrap(),yrs::MapPrelim::default());
      inner.insert(&mut txn,"title",yrs::TextPrelim::new(a[3].as_str().unwrap()));
      let list=inner.insert(&mut txn,"list",yrs::ArrayPrelim::default());
      let row=list.insert(&mut txn,0,yrs::MapPrelim::default());
      row.insert(&mut txn,"done",false);
    }
    "e" => {
      let mut txn=docs[x].transact_mut();
      if let Some(yrs::Out::YMap(inner))=maps[x].get(&txn,a[2].as_str().unwrap()) {
        if let Some(yrs::Out::YText(text))=inner.get(&txn,"title") {
          let pos=a[3].as_u64().unwrap() as u32 % (text.len(&txn)+1);
          text.insert(&mut txn,pos,"!");
        }
        if let Some(yrs::Out::YArray(list))=inner.get(&txn,"list") {
          if let Some(yrs::Out::YMap(row))=list.get(&txn,0) { row.insert(&mut txn,"done",true); }
          let len=list.len(&txn); list.insert(&mut txn,len,a[3].as_u64().unwrap() as i64);
        }
      }
    }
    "I" => { let mut txn=docs[x].transact_mut(); let n=arrays[x].len(&txn); let pos=a[2].as_u64().unwrap() as u32 % (n+1); let values: Vec<yrs::Any>=a[3].as_array().unwrap().iter().map(|v| serde_json::from_value(v.clone()).unwrap()).collect(); arrays[x].insert_range(&mut txn,pos,values); }
    "D" => { let mut txn=docs[x].transact_mut(); let n=arrays[x].len(&txn); let pos=a[2].as_u64().unwrap() as u32 % (n+1); let len=a[3].as_u64().unwrap() as u32 % (n-pos+1); arrays[x].remove_range(&mut txn,pos,len); }
    "m" => { let value: yrs::Any=serde_json::from_value(a[3].clone()).unwrap(); maps[x].insert(&mut docs[x].transact_mut(),a[2].as_str().unwrap(),value); }
    "M" => { maps[x].remove(&mut docs[x].transact_mut(),a[2].as_str().unwrap()); }
    "s" | "q" => { let y=a[2].as_u64().unwrap() as usize; let sv=docs[y].transact().state_vector(); let bytes=if v2 { docs[x].transact().encode_state_as_update_v2(&sv) } else { docs[x].transact().encode_state_as_update_v1(&sv) }; if kind=="q" {queued.push((y,bytes));} else { docs[y].transact_mut().apply_update(if v2 { Update::decode_v2(&bytes) } else { Update::decode_v1(&bytes) }.unwrap()).unwrap(); } }
    "r" => { if !queued.is_empty() { let (y,bytes)=&queued[x % queued.len()]; docs[*y].transact_mut().apply_update(if v2 { Update::decode_v2(bytes) } else { Update::decode_v1(bytes) }.unwrap()).unwrap(); } }
    "a" => { docs[x].transact_mut().apply_update(if v2 { Update::decode_v2(&unhex(a[2].as_str().unwrap())) } else { Update::decode_v1(&unhex(a[2].as_str().unwrap())) }.unwrap()).unwrap(); }
    _ => panic!("bad command")
   }
   if trace {
    for i in 0..3 {
     let txn=docs[i].transact();
     let bytes=if v2 { txn.encode_state_as_update_v2(&previous[i]) } else { txn.encode_state_as_update_v1(&previous[i]) };
     history.push(json!(["a",i,hex(&bytes)]));
     previous[i]=txn.state_vector();
    }
   }
   snapshots.push((0..3).map(|i| {let txn=docs[i].transact(); {
 let delta=texts[i].diff(&txn, |_| ()).into_iter().map(|c| { let mut v=json!({"insert":c.insert.to_json(&txn)}); if let Some(attrs)=c.attributes { v["attributes"]=serde_json::to_value(attrs).unwrap(); } v }).collect::<Vec<_>>();
 json!({"text":texts[i].get_string(&txn),"delta":delta,"array":arrays[i].to_json(&txn),"map":maps[i].to_json(&txn)})
 }}).collect::<Vec<_>>());
  }
  let updates=docs.iter().map(|d|hex(&if v2 { d.transact().encode_state_as_update_v2(&Default::default()) } else { d.transact().encode_state_as_update_v1(&Default::default()) })).collect::<Vec<_>>();
  let states=docs.iter().map(|d| {let mut v=d.transact().state_vector().iter().map(|(c,n)|(c.get(),*n)).collect::<Vec<_>>();v.sort();v}).collect::<Vec<_>>();
  println!("{}",json!({"snapshots":snapshots,"updates":updates,"states":states,"history":history,"local_cases":local_cases}));
 }
}
