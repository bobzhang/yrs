use std::io::{self, BufRead};
use std::sync::{Arc, Mutex};
use serde_json::{json, Value};
use yrs::{Doc, Options, ClientID, Text, Map, TextPrelim, Transact, ReadTxn, StateVector, Update, IdSet, ID, BranchID};
use yrs::undo::{UndoManager, Options as UndoOptions, Event};
use yrs::updates::{encoder::Encode, decoder::Decode};
fn ranges(set:&IdSet)->Value { json!(set.iter().flat_map(|(c,rs)| rs.iter().map(move |r|json!([c.get().to_string(),r.start,r.end]))).collect::<Vec<_>>()) }
fn parse_set(v:&Value)->IdSet { let mut s=IdSet::new(); for r in v.as_array().unwrap(){let start=r[1].as_u64().unwrap() as u32;let end=r[2].as_u64().unwrap() as u32;s.insert(ID::new(ClientID::new(r[0].as_u64().unwrap()),start),end-start);}s }
fn branch_id(id:BranchID)->Value {match id {BranchID::Root(s)=>json!(["root",s]),BranchID::Nested(id)=>json!(["nested",id.client.get().to_string(),id.clock])}}
fn record(events:&Arc<Mutex<Vec<Value>>>, name:&str, e:&mut Event<i32>) {
 let mut parents=e.changed_parent_types().iter().map(|p|branch_id(p.id())).collect::<Vec<_>>(); parents.sort_by_key(|p|p.to_string());
 events.lock().unwrap().push(json!([name,format!("{:?}",e.kind()),e.meta(),parents]));
 if name!="popped" { *e.meta_mut()+=1; }
}
fn subscribe(m:&mut UndoManager<i32>, events:&Arc<Mutex<Vec<Value>>>) {
 let log=events.clone();m.observe_item_added("added",move |_,e|record(&log,"added",e));
 let log=events.clone();m.observe_item_updated("updated",move |_,e|record(&log,"updated",e));
 let log=events.clone();m.observe_item_popped("popped",move |_,e|record(&log,"popped",e));
}
fn main(){for line in io::stdin().lock().lines(){let input:Value=serde_json::from_str(&line.unwrap()).unwrap();let result=match input[0].as_str().unwrap(){
 "sets"=>{let a=parse_set(&input[1]);let b=parse_set(&input[2]);let u=a.merge(&b);let d=a.diff(&b);let i=a.intersect(&b);json!({"a":ranges(&a),"union":ranges(&u),"diff":ranges(&d),"intersect":ranges(&i),"v1":a.encode_v1(),"v2":a.encode_v2(),"json":serde_json::to_value(a).unwrap()})},
 "undo" | "restore"=>{
  let restoring=input[0]=="restore";
  let mut doc=Doc::with_options(Options{client_id:ClientID::new(1),guid:"A".into(),skip_gc:true,offset_kind:yrs::OffsetKind::Utf16,..Options::default()});
  let mut root=doc.get_or_insert_map("root");let mut text=root.insert(&mut doc.transact_mut(),"text",TextPrelim::new(""));
  let mut manager=UndoManager::<i32>::with_options(UndoOptions{capture_timeout_millis:u64::MAX,..UndoOptions::default()});manager.expand_scope(&doc,&root);
  if restoring {
    doc=Doc::with_options(Options{client_id:ClientID::new(input[1].as_u64().unwrap()),guid:"A".into(),skip_gc:true,offset_kind:yrs::OffsetKind::Utf16,..Options::default()});
    let state:Vec<u8>=serde_json::from_value(input[2].clone()).unwrap();doc.transact_mut().apply_update(Update::decode_v1(&state).unwrap()).unwrap();
    root=doc.get_or_insert_map("root");text=root.get(&doc.transact(),"text").unwrap().cast().unwrap();
    manager=UndoManager::with_options(UndoOptions{capture_timeout_millis:u64::MAX,init_undo_stack:serde_json::from_value(input[3].clone()).unwrap(),init_redo_stack:serde_json::from_value(input[4].clone()).unwrap(),..UndoOptions::default()});manager.expand_scope(&doc,&root);
  }
  let events=Arc::new(Mutex::new(Vec::new()));subscribe(&mut manager,&events);let mut rows=Vec::new();
  for command in input[if restoring{5}else{1}].as_array().unwrap(){let mut changed=None;match command[0].as_str().unwrap(){
   "i"=>{let at=(command[1].as_u64().unwrap() as u32)%(text.len(&doc.transact())+1);text.insert(&mut doc.transact_mut(),at,command[2].as_str().unwrap());},
   "d"=>{let len=text.len(&doc.transact());if len>0{let at=command[1].as_u64().unwrap() as u32%len;let n=(command[2].as_u64().unwrap() as u32).min(len-at);text.remove_range(&mut doc.transact_mut(),at,n);}},
   "reset"=>manager.reset(),"undo"=>changed=Some(manager.undo_blocking()),"redo"=>changed=Some(manager.redo_blocking()),
   "reload"=>{let state=doc.transact().encode_state_as_update_v1(&StateVector::default());let us=serde_json::to_value(manager.undo_stack()).unwrap();let rs=serde_json::to_value(manager.redo_stack()).unwrap();
    let client=doc.client_id().get()+1;doc=Doc::with_options(Options{client_id:ClientID::new(client),guid:"A".into(),skip_gc:true,offset_kind:yrs::OffsetKind::Utf16,..Options::default()});
    doc.transact_mut().apply_update(Update::decode_v1(&state).unwrap()).unwrap();root=doc.get_or_insert_map("root");text=root.get(&doc.transact(),"text").unwrap().cast().unwrap();
    manager=UndoManager::with_options(UndoOptions{capture_timeout_millis:u64::MAX,init_undo_stack:serde_json::from_value(us).unwrap(),init_redo_stack:serde_json::from_value(rs).unwrap(),..UndoOptions::default()});manager.expand_scope(&doc,&root);subscribe(&mut manager,&events);
   },
   _=>panic!("unknown command")
  }
  let mut row=json!({"text":yrs::GetString::get_string(&text,&doc.transact()),"changed":changed,"undo":manager.undo_stack(),"redo":manager.redo_stack(),"events":std::mem::take(&mut *events.lock().unwrap())});
  if !restoring {row["state"]=json!(doc.transact().encode_state_as_update_v1(&StateVector::default()));row["client"]=json!(doc.client_id().get());}
  rows.push(row);
  }
  json!(rows)
 },_=>panic!("unknown case")};println!("{}",result);}}
