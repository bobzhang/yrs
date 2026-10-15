use std::{io::{self,BufRead},sync::{Arc,Mutex}};
use serde_json::{Value,json};
use yrs::{Observable,Doc,Options,OffsetKind,Text,GetString,Map,ReadTxn,Transact,Update,TransactionMut};
use yrs::updates::decoder::Decode;
fn hex(b:&[u8])->String{b.iter().map(|b|format!("{b:02x}")).collect()}
fn ranges(set:&yrs::IdSet)->Vec<(u64,u32,u32)>{let mut r=vec![];for (id,rs) in set.iter(){for range in rs.iter(){r.push((id.get(),range.start,range.end))}}r.sort();r}
fn meta(tx:&TransactionMut, doc:usize, phase:&str)->Value{
 let mut before=tx.before_state().iter().map(|(c,n)|(c.get(),*n)).collect::<Vec<_>>();before.sort();
 let mut after=tx.after_state().iter().map(|(c,n)|(c.get(),*n)).collect::<Vec<_>>();after.sort();
 json!({"doc":doc,"phase":phase,"before":before,"after":after,"inserted":ranges(tx.insert_set()),"deleted":ranges(tx.delete_set()),"origin":tx.origin().map(|o|hex(o.as_ref()))})
}
fn main(){
 let v2=std::env::args().any(|s|s=="v2");
 for line in io::stdin().lock().lines(){
  let commands:Vec<Value>=serde_json::from_str(&line.unwrap()).unwrap();
  let docs:Vec<_>=(1..=3).map(|id|{let mut o=Options::with_client_id(yrs::block::ClientID::new(id));o.skip_gc=true;o.offset_kind=OffsetKind::Utf16;Doc::with_options(o)}).collect();
  let texts:Vec<_>=docs.iter().map(|d|d.get_or_insert_text("note")).collect();let maps:Vec<_>=docs.iter().map(|d|d.get_or_insert_map("settings")).collect();
  let events=Arc::new(Mutex::new(vec![]));let packets=Arc::new(Mutex::new(vec![]));let mut snapshots=vec![];
  for (i,d) in docs.iter().enumerate(){
   let log=events.clone();d.observe_before_observer_calls("oracle",move|tx|{log.lock().unwrap().push(meta(tx,i,"before"))}).unwrap();
   let log=events.clone();d.observe_after_transaction("oracle",move|tx|{log.lock().unwrap().push(meta(tx,i,"after"))}).unwrap();
   let log=events.clone();d.observe_transaction_cleanup("oracle",move|tx,_|{log.lock().unwrap().push(meta(tx,i,"cleanup"))}).unwrap();
   let log=events.clone();let out=packets.clone();d.observe_update_v1("oracle",move|tx,e|{log.lock().unwrap().push(meta(tx,i,"v1"));out.lock().unwrap().push((i,false,e.update.clone()))}).unwrap();
   let log=events.clone();let out=packets.clone();d.observe_update_v2("oracle",move|tx,e|{log.lock().unwrap().push(meta(tx,i,"v2"));out.lock().unwrap().push((i,true,e.update.clone()))}).unwrap();
  }
  for (i,map) in maps.iter().enumerate(){
   let log=events.clone();map.observe("oracle",move|tx,event|{
    use yrs::types::{EntryChange,ToJson};
    let mut changes=serde_json::Map::new();
    for (key,change) in event.keys(tx){
     let value=match change {
      EntryChange::Inserted(value)=>json!({"action":"add","new_value":value.to_json(tx)}),
      EntryChange::Updated(old,value)=>json!({"action":"update","old_value":old.to_json(tx),"new_value":value.to_json(tx)}),
      EntryChange::Removed(value)=>json!({"action":"delete","old_value":value.to_json(tx)})
     };
     changes.insert(key.to_string(),value);
    }
    log.lock().unwrap().push(json!({"doc":i,"phase":"map","changes":changes}));
   });
  }
  let shadows:Vec<_>=(0..6).map(|i|{let mut o=Options::with_client_id(yrs::block::ClientID::new(100+i));o.skip_gc=true;Doc::with_options(o)}).collect();
  let shadow_texts:Vec<_>=shadows.iter().map(|d|d.get_or_insert_text("note")).collect();
  let shadow_maps:Vec<_>=shadows.iter().map(|d|d.get_or_insert_map("settings")).collect();
  for c in commands{
   events.lock().unwrap().clear();packets.lock().unwrap().clear();let x=c[1].as_u64().unwrap() as usize;
   if c[0]=="sync"{
    let y=c[2].as_u64().unwrap() as usize;let sv=docs[y].transact().state_vector();let tx=docs[x].transact();let u=if v2{Update::decode_v2(&tx.encode_state_as_update_v2(&sv))}else{Update::decode_v1(&tx.encode_state_as_update_v1(&sv))}.unwrap();drop(tx);docs[y].transact_mut_with("remote").apply_update(u).unwrap();
   }else{
    let mut tx=docs[x].transact_mut_with(c[3].as_str().unwrap());
    for op in c[2].as_array().unwrap(){
     match op[0].as_str().unwrap(){
      "i"|"t"=>{let p=op[1].as_u64().unwrap() as u32%(texts[x].len(&tx)+1);if op[0]=="i"{texts[x].insert(&mut tx,p,op[2].as_str().unwrap())}else{let attrs=std::collections::HashMap::from([(Arc::from("bold"),yrs::Any::Bool(op[3].as_bool().unwrap()))]);texts[x].insert_with_attributes(&mut tx,p,op[2].as_str().unwrap(),attrs)}},
      "d"|"f"=>{let n=texts[x].len(&tx);let p=op[1].as_u64().unwrap() as u32%(n+1);let len=op[2].as_u64().unwrap() as u32%(n-p+1);if op[0]=="d"{texts[x].remove_range(&mut tx,p,len)}else{texts[x].format(&mut tx,p,len,std::collections::HashMap::from([(Arc::from("bold"),yrs::Any::Bool(op[3].as_bool().unwrap()))]))}},
      "m"=>{maps[x].insert(&mut tx,op[1].as_str().unwrap(),op[2].as_i64().unwrap());},
      "M"=>{maps[x].remove(&mut tx,op[1].as_str().unwrap());},
      _=>panic!("operation")
     }
    }
   }
   for (i,v2,bytes) in packets.lock().unwrap().drain(..){let index=i*2+v2 as usize;shadows[index].transact_mut().apply_update(if v2{Update::decode_v2(&bytes)}else{Update::decode_v1(&bytes)}.unwrap()).unwrap();}
   use yrs::types::ToJson;
   let current:Vec<_>=docs.iter().enumerate().map(|(i,d)|{let tx=d.transact();json!({"text":texts[i].get_string(&tx),"map":maps[i].to_json(&tx)})}).collect();
   let replay:Vec<_>=shadows.iter().enumerate().map(|(i,d)|{let tx=d.transact();json!({"text":shadow_texts[i].get_string(&tx),"map":shadow_maps[i].to_json(&tx)})}).collect();
   snapshots.push(json!({"docs":current,"events":*events.lock().unwrap(),"replayed":replay}));
  }
  println!("{}",json!({"snapshots":snapshots}));
 }
}
