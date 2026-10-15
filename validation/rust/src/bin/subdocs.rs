use std::{io::{self,BufRead},sync::{Arc,Mutex}};
use serde_json::{Value,json};
use yrs::{Doc,Options,OffsetKind,ReadTxn,Transact,Update,Map,Out,Text,GetString};
use yrs::updates::decoder::Decode;
fn hex(bytes:&[u8])->String{bytes.iter().map(|b|format!("{b:02x}")).collect()}
fn unhex(s:&str)->Vec<u8>{(0..s.len()).step_by(2).map(|i|u8::from_str_radix(&s[i..i+2],16).unwrap()).collect()}
fn guids<'a>(docs:impl Iterator<Item=&'a Doc>)->Vec<String>{let mut r:Vec<_>=docs.map(|d|d.guid().to_string()).collect();r.sort();r}
fn description(d:&Doc)->Value{let text=d.get_or_insert_text("body").get_string(&d.transact());json!({"guid":d.guid().as_ref(),"auto":d.auto_load(),"load":d.should_load(),"client":d.client_id().get(),"collection":d.collection_id(),"text":text,"parent":d.parent_doc().is_some()})}
fn main(){let v2=std::env::args().any(|s|s=="v2");for line in io::stdin().lock().lines(){
 let commands:Vec<Value>=serde_json::from_str(&line.unwrap()).unwrap();
 let docs:Vec<_>=(1..=3).map(|i|{let mut o=Options::with_client_id(yrs::block::ClientID::new(i));o.skip_gc=true;o.offset_kind=OffsetKind::Utf16;o.collection_id=Some(Arc::from("workspace"));Doc::with_options(o)}).collect();
 let roots:Vec<_>=docs.iter().map(|d|d.get_or_insert_map("files")).collect();let log=Arc::new(Mutex::new(vec![]));
 for i in 0..3{let l=log.clone();docs[i].observe_subdocs("events",move|_,e|{l.lock().unwrap().push(json!({"doc":i,"added":guids(e.added()),"removed":guids(e.removed()),"loaded":guids(e.loaded())}));}).unwrap();}
 let mut snapshots=vec![];
 for c in commands{log.lock().unwrap().clear();let x=c[1].as_u64().unwrap()as usize;let op=c[0].as_str().unwrap();
 if op=="apply"||op=="sync"{let (target,bytes)=if op=="apply"{(x,unhex(c[2].as_str().unwrap()))}else{let y=c[2].as_u64().unwrap()as usize;let sv=docs[y].transact().state_vector();let tx=docs[x].transact();(y,if v2{tx.encode_state_as_update_v2(&sv)}else{tx.encode_state_as_update_v1(&sv)})};docs[target].transact_mut().apply_update(if v2{Update::decode_v2(&bytes)}else{Update::decode_v1(&bytes)}.unwrap()).unwrap();}
 else{let key=c[2].as_str().unwrap();if op=="put"{let mut o=Options::with_client_id(yrs::block::ClientID::new(99));o.guid=c[3].as_str().unwrap().into();o.auto_load=c[4].as_bool().unwrap();o.should_load=c[5].as_bool().unwrap();o.skip_gc=true;o.offset_kind=OffsetKind::Utf16;roots[x].insert(&mut docs[x].transact_mut(),key,Doc::with_options(o));}
 else if op=="remove"{roots[x].remove(&mut docs[x].transact_mut(),key);}
 else{let child=roots[x].get(&docs[x].transact(),key);if let Some(Out::YDoc(child))=child{match op{
 "load"=>child.load(&mut docs[x].transact_mut()),
 "destroy"=>child.destroy(Some(&mut docs[x].transact_mut())),
 "edit"=>{let t=child.get_or_insert_text("body");let mut tx=child.transact_mut();let len=t.len(&tx);t.insert(&mut tx,len,c[3].as_str().unwrap());},
 "childsync"=>{let y=c[3].as_u64().unwrap()as usize;let target=roots[y].get(&docs[y].transact(),key);if let Some(Out::YDoc(target))=target{if child.guid()==target.guid(){let sv=target.transact().state_vector();let tx=child.transact();let bytes=if v2{tx.encode_state_as_update_v2(&sv)}else{tx.encode_state_as_update_v1(&sv)};drop(tx);target.transact_mut().apply_update(if v2{Update::decode_v2(&bytes)}else{Update::decode_v1(&bytes)}.unwrap()).unwrap();}}},_=>panic!("op")}}}}
 let current:Vec<_>=docs.iter().enumerate().map(|(i,d)|{let tx=d.transact();let files:serde_json::Map<_,_>=roots[i].iter(&tx).filter_map(|(k,v)|if let Out::YDoc(d)=v{Some((k.to_owned(),description(&d)))}else{None}).collect();let registered=guids(tx.subdocs());json!({"files":files,"registered":registered})}).collect();snapshots.push(json!({"docs":current,"events":*log.lock().unwrap()}));
 }
 let updates:Vec<_>=docs.iter().map(|d|{let tx=d.transact();hex(&if v2{tx.encode_state_as_update_v2(&yrs::StateVector::default())}else{tx.encode_state_as_update_v1(&yrs::StateVector::default())})}).collect();println!("{}",json!({"snapshots":snapshots,"updates":updates}));
}}
