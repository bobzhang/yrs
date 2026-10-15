use std::{io::{self,BufRead},sync::{Arc,Mutex}};
use serde_json::{Value,json};
use yrs::{Doc,Options,OffsetKind,ReadTxn,Transact,Update,Text,GetString,Observable,TransactionMut};
use yrs::types::{Delta,ToJson};
use yrs::updates::decoder::Decode;
fn delta(d:&[Delta],tx:&TransactionMut)->Value{
 Value::Array(d.iter().map(|op|{let mut out=serde_json::Map::new();let attrs=match op{
 Delta::Inserted(v,a)=>{out.insert("insert".into(),serde_json::to_value(v.to_json(tx)).unwrap());a.as_ref()},
 Delta::Deleted(n)=>{out.insert("delete".into(),json!(n));None},
 Delta::Retain(n,a)=>{out.insert("retain".into(),json!(n));a.as_ref()}};
 if let Some(a)=attrs {if !a.is_empty(){out.insert("attributes".into(),serde_json::to_value(a).unwrap());}}Value::Object(out)}).collect())
}

fn hex(bytes:&[u8])->String{bytes.iter().map(|b|format!("{b:02x}")).collect()}
fn unhex(s:&str)->Vec<u8>{(0..s.len()).step_by(2).map(|i|u8::from_str_radix(&s[i..i+2],16).unwrap()).collect()}
fn main(){let v2=std::env::args().any(|s|s=="v2");for line in io::stdin().lock().lines(){
 let commands:Vec<Value>=serde_json::from_str(&line.unwrap()).unwrap();
 let docs:Vec<_>=(1..=3).map(|i|{let mut o=Options::with_client_id(yrs::block::ClientID::new(i));o.skip_gc=true;o.offset_kind=if i==2{OffsetKind::Utf16}else{OffsetKind::Bytes};Doc::with_options(o)}).collect();
 let texts:Vec<_>=docs.iter().map(|d|d.get_or_insert_text("text")).collect();let log=Arc::new(Mutex::new(vec![]));
 for i in 0..3{let l=log.clone();texts[i].observe("events",move|tx,e|{l.lock().unwrap().push(json!({"doc":i,"delta":delta(e.delta(tx),tx)}));});}
 let mut snapshots=vec![];
 for c in commands{log.lock().unwrap().clear();let x=c[1].as_u64().unwrap()as usize;let op=c[0].as_str().unwrap();
 if op=="apply"||op=="sync"{let (target,bytes)=if op=="apply"{(x,unhex(c[2].as_str().unwrap()))}else{let y=c[2].as_u64().unwrap()as usize;let sv=docs[y].transact().state_vector();let tx=docs[x].transact();(y,if v2{tx.encode_state_as_update_v2(&sv)}else{tx.encode_state_as_update_v1(&sv)})};docs[target].transact_mut().apply_update(if v2{Update::decode_v2(&bytes)}else{Update::decode_v1(&bytes)}.unwrap()).unwrap();}
 else {let mut tx=docs[x].transact_mut();let s=texts[x].get_string(&tx);let mut points=vec![0u32];for ch in s.chars(){points.push(points.last().unwrap()+if x==1{ch.len_utf16()as u32}else{ch.len_utf8()as u32});}let p=c[2].as_u64().unwrap()as usize%points.len();
 if op=="i"{texts[x].insert(&mut tx,points[p],c[3].as_str().unwrap());}
 else{let end=p+c[3].as_u64().unwrap()as usize%(points.len()-p);let count=points[end]-points[p];if op=="d"{texts[x].remove_range(&mut tx,points[p],count);}else{texts[x].format(&mut tx,points[p],count,std::collections::HashMap::from([(Arc::from("bold"),yrs::Any::Bool(c[4]==1))]));}}}
 let current:Vec<_>=docs.iter().enumerate().map(|(i,d)|{let tx=d.transact();let mut sv:Vec<_>=tx.state_vector().iter().map(|(c,n)|json!([c.get(),n])).collect();sv.sort_by_key(|v|v[0].as_u64());let dif:Vec<_>=texts[i].diff(&tx,yrs::types::text::YChange::identity).into_iter().map(|v|{let mut j=json!({"insert":v.insert.to_json(&tx)});if let Some(a)=v.attributes{if !a.is_empty(){j["attributes"]=json!(a);}}j}).collect();json!({"text":texts[i].get_string(&tx),"length":texts[i].len(&tx),"delta":dif,"sv":sv})}).collect();snapshots.push(json!({"docs":current,"events":*log.lock().unwrap()}));
 }
 let updates:Vec<_>=docs.iter().map(|d|{let tx=d.transact();hex(&if v2{tx.encode_state_as_update_v2(&yrs::StateVector::default())}else{tx.encode_state_as_update_v1(&yrs::StateVector::default())})}).collect();println!("{}",json!({"snapshots":snapshots,"updates":updates}));
}}
