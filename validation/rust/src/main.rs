use std::io::{self, BufRead};
use yrs::{Doc, Text, GetString, ReadTxn, Transact, Options, OffsetKind, Update};
use yrs::updates::decoder::Decode;
use serde_json::{Value, json};
fn hex(b: &[u8]) -> String { b.iter().map(|b| format!("{b:02x}")).collect() }
fn unhex(s: &str) -> Vec<u8> { (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i+2],16).unwrap()).collect() }
fn main() {
 for line in io::stdin().lock().lines() {
  let commands: Vec<Value> = serde_json::from_str(&line.unwrap()).unwrap();
  let docs: Vec<Doc> = (1..=3).map(|i| { let mut o=Options::with_client_id(yrs::block::ClientID::new(i)); o.offset_kind=OffsetKind::Utf16; o.skip_gc=true; Doc::with_options(o) }).collect();
  let texts: Vec<_> = docs.iter().map(|d| d.get_or_insert_text("note")).collect();
  let mut queued: Vec<(usize,Vec<u8>)> = vec![];
  let mut snapshots=vec![];
  for cmd in commands {
   let a=cmd.as_array().unwrap();
   let kind=a[0].as_str().unwrap();
   let x=a[1].as_u64().unwrap() as usize;
   match kind {
    "i" => { let mut txn=docs[x].transact_mut(); let n=texts[x].len(&txn); let pos=a[2].as_u64().unwrap() as u32 % (n+1); texts[x].insert(&mut txn,pos,a[3].as_str().unwrap()); }
    "d" => { let mut txn=docs[x].transact_mut(); let n=texts[x].len(&txn); let pos=a[2].as_u64().unwrap() as u32 % (n+1); let len=a[3].as_u64().unwrap() as u32 % (n-pos+1); texts[x].remove_range(&mut txn,pos,len); }
    "s" | "q" => { let y=a[2].as_u64().unwrap() as usize; let sv=docs[y].transact().state_vector(); let bytes=docs[x].transact().encode_state_as_update_v1(&sv); if kind=="q" {queued.push((y,bytes));} else { docs[y].transact_mut().apply_update(Update::decode_v1(&bytes).unwrap()).unwrap(); } }
    "r" => { if !queued.is_empty() { let (y,bytes)=&queued[x % queued.len()]; docs[*y].transact_mut().apply_update(Update::decode_v1(bytes).unwrap()).unwrap(); } }
    "a" => { docs[x].transact_mut().apply_update(Update::decode_v1(&unhex(a[2].as_str().unwrap())).unwrap()).unwrap(); }
    _ => panic!("bad command")
   }
   snapshots.push(docs.iter().zip(&texts).map(|(d,t)|t.get_string(&d.transact())).collect::<Vec<_>>());
  }
  let updates=docs.iter().map(|d|hex(&d.transact().encode_state_as_update_v1(&Default::default()))).collect::<Vec<_>>();
  let states=docs.iter().map(|d| {let mut v=d.transact().state_vector().iter().map(|(c,n)|(c.get(),*n)).collect::<Vec<_>>();v.sort();v}).collect::<Vec<_>>();
  println!("{}",json!({"snapshots":snapshots,"updates":updates,"states":states}));
 }
}
