use std::{io::{self,BufRead},sync::{Arc,Mutex,atomic::{AtomicU64,Ordering}}};
use serde_json::{Value,json};
use yrs::{Doc,Text,GetString,Transact};
use yrs::sync::{Awareness,DefaultProtocol,Protocol,Message};
use yrs::sync::awareness::AwarenessUpdate;
use yrs::updates::{decoder::Decode,encoder::{Encode,Encoder}};
fn hex(b:&[u8])->String {b.iter().map(|b|format!("{b:02x}")).collect()}
fn unhex(s:&str)->Vec<u8> {(0..s.len()).step_by(2).map(|i|u8::from_str_radix(&s[i..i+2],16).unwrap()).collect()}
fn main(){
 for line in io::stdin().lock().lines(){
  let commands:Vec<Value>=serde_json::from_str(&line.unwrap()).unwrap();
  let now=Arc::new(AtomicU64::new(0));let events=Arc::new(Mutex::new(vec![]));
  let mut docs:Vec<_>=(1..=3).map(|id|{
   let clock=now.clone();let mut a=Awareness::with_clock(Doc::with_client_id(id),move||clock.load(Ordering::SeqCst));
   for kind in ["change","update"]{
    let events=events.clone();let callback=move|_:&Awareness,e:&yrs::sync::awareness::Event,_:Option<&yrs::Origin>|{
     let mut added=e.added().iter().map(|x|x.get()).collect::<Vec<_>>();added.sort();
     let mut updated=e.updated().iter().map(|x|x.get()).collect::<Vec<_>>();updated.sort();
     let mut removed=e.removed().iter().map(|x|x.get()).collect::<Vec<_>>();removed.sort();
     events.lock().unwrap().push(json!([id-1,kind,added,updated,removed]));
    };
    if kind=="change" {a.on_change("oracle",callback)}else{a.on_update("oracle",callback)}
   }
   a
  }).collect();
  let mut queued=vec![];let mut snapshots=vec![];let protocol=DefaultProtocol;
  for (step,c) in commands.iter().enumerate(){
   now.store(step as u64+1000,Ordering::SeqCst);events.lock().unwrap().clear();
   let x=c[1].as_u64().unwrap() as usize;
   match c[0].as_str().unwrap(){
    "set"=>docs[x].set_local_state_raw(c[2].as_str().unwrap()),
    "remove"=>docs[x].remove_state(yrs::block::ClientID::new(c[2].as_u64().unwrap())),
    "send"|"queue"=>{
     let y=c[2].as_u64().unwrap() as usize;
     let update=if c.as_array().unwrap().len()>3 {docs[x].update_with_clients(c[3].as_array().unwrap().iter().map(|v|yrs::block::ClientID::new(v.as_u64().unwrap()))).unwrap()}else{docs[x].update().unwrap()};
     let bytes=update.encode_v1();
     if c[0]=="send" {docs[y].apply_update(AwarenessUpdate::decode_v1(&bytes).unwrap()).unwrap()}else{queued.push((y,bytes))}
    }
    "deliver"=>{if !queued.is_empty(){let (y,bytes)=&queued[x%queued.len()];docs[*y].apply_update(AwarenessUpdate::decode_v1(bytes).unwrap()).unwrap()}},
    "apply"=>{docs[x].apply_update(AwarenessUpdate::decode_v1(&unhex(c[2].as_str().unwrap())).unwrap()).unwrap()},
    "insert"=>{let text=docs[x].doc().get_or_insert_text("note");let mut tx=docs[x].doc().transact_mut();let n=text.len(&tx);text.insert(&mut tx,n,c[2].as_str().unwrap())},
    "connect"=>{
     let y=c[2].as_u64().unwrap() as usize;
     let mut encoder=yrs::updates::encoder::EncoderV1::new();protocol.start(&docs[x],&mut encoder).unwrap();
     let responses=protocol.handle(&mut docs[y],&encoder.to_vec()).unwrap();
     for response in responses {protocol.handle(&mut docs[x],&response.encode_v1()).unwrap();}
    }
    "query"=>{
     let y=c[2].as_u64().unwrap() as usize;
     let response=protocol.handle_message(&mut docs[y],Message::AwarenessQuery).unwrap().unwrap();
     protocol.handle_message(&mut docs[x],response).unwrap();
    }
    _=>panic!("bad operation")
   }
   let states:Vec<_>=docs.iter().map(|a|{
    let mut states=a.iter().map(|(id,s)|json!([id.get(),s.clock,s.last_updated,s.data])).collect::<Vec<_>>();states.sort_by_key(|s|s[0].as_u64().unwrap());
    let text=a.doc().get_or_insert_text("note").get_string(&a.doc().transact());json!({"states":states,"text":text})
   }).collect();
   snapshots.push(json!({"docs":states,"events":*events.lock().unwrap()}));
  }
  let updates:Vec<_>=docs.iter().map(|a|hex(&a.update().unwrap().encode_v1())).collect();
  println!("{}",json!({"snapshots":snapshots,"updates":updates}));
 }
}
