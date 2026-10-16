fn xml_snapshot(node: yrs::XmlOut, txn: &yrs::Transaction) -> Value {
 match node {
  yrs::XmlOut::Element(e) => {
   let attrs:serde_json::Map<String,Value>=e.attributes(txn).map(|(k,v)|(k.to_string(),serde_json::to_value(v.to_json(txn)).unwrap())).collect();
   json!({"tag":e.tag().as_ref(),"attributes":attrs,"children":e.children(txn).map(|c|xml_snapshot(c,txn)).collect::<Vec<_>>()})
  }
  yrs::XmlOut::Fragment(f) => json!({"children":f.children(txn).map(|c|xml_snapshot(c,txn)).collect::<Vec<_>>()}),
  yrs::XmlOut::Text(t) => {
   let attrs:serde_json::Map<String,Value>=t.attributes(txn).map(|(k,v)|(k.to_string(),serde_json::to_value(v.to_json(txn)).unwrap())).collect();
   json!({"text":t.get_string(txn),"attributes":attrs})
  }
 }
}

use std::{io::{self,BufRead,Write},sync::{Arc,Mutex}};
use serde_json::{Value,json};
use yrs::{Array,Map,Text,Xml,XmlFragment,Doc,Options,OffsetKind,ReadTxn,Transact,Update,DeepObservable,Observable,GetString,TransactionMut,Out};
use yrs::types::{Event,PathSegment,ToJson,Delta,Change,EntryChange};
use yrs::updates::decoder::Decode;
fn keys(k:&std::collections::HashMap<Arc<str>,EntryChange>,tx:&TransactionMut)->Value{
 Value::Object(k.iter().map(|(k,v)|(k.to_string(),match v{
 EntryChange::Inserted(v)=>json!({"action":"add","new_value":v.to_json(tx)}),
 EntryChange::Updated(a,b)=>json!({"action":"update","old_value":a.to_json(tx),"new_value":b.to_json(tx)}),
 EntryChange::Removed(v)=>json!({"action":"delete","old_value":v.to_json(tx)})})).collect())
}
fn delta(d:&[Delta],tx:&TransactionMut)->Value{
 Value::Array(d.iter().map(|op|{let mut out=serde_json::Map::new();let attrs=match op{
 Delta::Inserted(v,a)=>{out.insert("insert".into(),serde_json::to_value(v.to_json(tx)).unwrap());a.as_ref()},
 Delta::Deleted(n)=>{out.insert("delete".into(),json!(n));None},
 Delta::Retain(n,a)=>{out.insert("retain".into(),json!(n));a.as_ref()}};
 if let Some(a)=attrs {if !a.is_empty(){out.insert("attributes".into(),serde_json::to_value(a).unwrap());}}Value::Object(out)}).collect())
}
fn changes(d:&[Change],tx:&TransactionMut)->Value{Value::Array(d.iter().map(|op|match op{
 Change::Added(v)=>json!({"insert":v.iter().map(|v|v.to_json(tx)).collect::<Vec<_>>()}),
 Change::Removed(n)=>json!({"delete":n}),Change::Retain(n)=>json!({"retain":n})}).collect())}
fn event(e:&Event,tx:&TransactionMut)->Value{
 let path:Vec<_>=e.path().iter().map(|p|match p{PathSegment::Key(k)=>json!(k.as_ref()),PathSegment::Index(i)=>json!(i)}).collect();
 let mut out=json!({"path":path,"target":e.target().to_json(tx)});
 match e {
 Event::Weak(_)=>{out["kind"]=json!("weak");},
 Event::Text(e)=>{out["kind"]=json!("text");out["delta"]=delta(e.delta(tx),tx)},
 Event::Array(e)=>{out["kind"]=json!("array");out["delta"]=changes(e.delta(tx),tx)},
 Event::Map(e)=>{out["kind"]=json!("map");out["keys"]=keys(e.keys(tx),tx)},
 Event::XmlFragment(e)=>{out["kind"]=json!("xml");out["delta"]=changes(e.delta(tx),tx);out["keys"]=keys(e.keys(tx),tx);out["children"]=json!(e.children_changed());},
 Event::XmlText(e)=>{out["kind"]=json!("xmltext");out["delta"]=delta(e.delta(tx),tx);out["keys"]=keys(e.keys(tx),tx);}
 }
 out
}
fn hex(bytes:&[u8])->String{bytes.iter().map(|b|format!("{b:02x}")).collect()}
fn unhex(s:&str)->Vec<u8>{(0..s.len()).step_by(2).map(|i|u8::from_str_radix(&s[i..i+2],16).unwrap()).collect()}
fn main(){let v2=std::env::args().any(|s|s=="v2");let live=std::env::args().any(|s|s=="--live");let stdin=io::stdin();let mut lines=stdin.lock().lines();while let Some(line)=lines.next(){
 let mut commands:Vec<Value>=serde_json::from_str(&line.unwrap()).unwrap();
 let docs:Vec<_>=(1..=3).map(|i|{let mut o=Options::with_client_id(yrs::block::ClientID::new(i));o.skip_gc=true;o.offset_kind=OffsetKind::Utf16;Doc::with_options(o)}).collect();
 let roots:Vec<_>=docs.iter().map(|d|d.get_or_insert_map("root")).collect();let xmls:Vec<_>=docs.iter().map(|d|d.get_or_insert_xml_fragment("xml")).collect();
 let texts:Vec<_>=docs.iter().map(|d|d.get_or_insert_text("text")).collect();
 let tick=Arc::new(std::sync::atomic::AtomicU64::new(100));
 let mut managers:Vec<yrs::UndoManager>=docs.iter().enumerate().map(|(i,d)|{let mut o=yrs::undo::Options::default();let t=tick.clone();o.timestamp=Arc::new(move||t.load(std::sync::atomic::Ordering::Relaxed));o.capture_timeout_millis=500;let mut m=yrs::UndoManager::with_options(o);m.expand_scope(d,&roots[i]);m.expand_scope(d,&xmls[i]);m.expand_scope(d,&texts[i]);m.include_origin("user");m}).collect();
 let log=Arc::new(Mutex::new(vec![]));
 for i in 0..3{let l=log.clone();roots[i].observe_deep("deep",move|tx,es|{l.lock().unwrap().push(json!({"doc":i,"scope":"map","events":es.iter().map(|e|event(e,tx)).collect::<Vec<_>>()}));});
 let l=log.clone();xmls[i].observe_deep("deep",move|tx,es|{l.lock().unwrap().push(json!({"doc":i,"scope":"xml","events":es.iter().map(|e|event(e,tx)).collect::<Vec<_>>()}));});
 let l=log.clone();xmls[i].observe("shallow",move|tx,e|{l.lock().unwrap().push(json!({"doc":i,"scope":"shallow","delta":changes(e.delta(tx),tx),"keys":keys(e.keys(tx),tx),"children":e.children_changed()}));});}
 let mut snapshots=vec![];
 loop { for command in commands{log.lock().unwrap().clear();let x=command[1].as_u64().unwrap() as usize;
 let mut result=Value::Null;
 if command[0]=="apply"{let bytes=unhex(command[2].as_str().unwrap());docs[x].transact_mut().apply_update(if v2{Update::decode_v2(&bytes)}else{Update::decode_v1(&bytes)}.unwrap()).unwrap();}
 else if command[0]=="undo"{result=json!(managers[x].undo_blocking());}
 else if command[0]=="redo"{result=json!(managers[x].redo_blocking());}
 else if command[0]=="reset"{managers[x].reset();}
 else if command[0]=="tick"{tick.fetch_add(command[2].as_u64().unwrap(),std::sync::atomic::Ordering::Relaxed);}
 else if command[0]=="clear"{managers[x].clear_all();}
 else if command[0]=="sync"{let y=command[2].as_u64().unwrap() as usize;let sv=docs[y].transact().state_vector();let tx=docs[x].transact();let u=if v2{Update::decode_v2(&tx.encode_state_as_update_v2(&sv))}else{Update::decode_v1(&tx.encode_state_as_update_v1(&sv))}.unwrap();drop(tx);docs[y].transact_mut().apply_update(u).unwrap();}
 else{let mut tx=docs[x].transact_mut_with("user");for op in command[2].as_array().unwrap(){let n=op[1].as_u64().unwrap() as u32;let key=format!("key{}",n%3);
 match op[0].as_str().unwrap(){
 "i"=>{let p=n%(texts[x].len(&tx)+1);texts[x].insert(&mut tx,p,"abc");},
 "d"=>{let len=texts[x].len(&tx);let p=n%(len+1);let count=(n/3)%(len-p+1);texts[x].remove_range(&mut tx,p,count);},
 "f"=>{let len=texts[x].len(&tx);let p=n%(len+1);let count=(n/3)%(len-p+1);texts[x].format(&mut tx,p,count,std::collections::HashMap::from([(Arc::from("bold"),yrs::Any::Bool(n%2==0))]));},
 "m"=>{roots[x].insert(&mut tx,key.as_str(),n as i64);},
 "new"=>{let m=roots[x].insert(&mut tx,key.as_str(),yrs::MapPrelim::default());m.insert(&mut tx,"title",yrs::TextPrelim::new("hello"));let a=m.insert(&mut tx,"list",yrs::ArrayPrelim::default());let row=a.insert(&mut tx,0,yrs::MapPrelim::default());row.insert(&mut tx,"done",false);},
 "remove"=>{roots[x].remove(&mut tx,&key);},
 "edit"|"shift"=>{if let Some(Out::YMap(m))=roots[x].get(&tx,&key){if let Some(Out::YText(t))=m.get(&tx,"title"){let p=n%(t.len(&tx)+1);t.insert(&mut tx,p,"!");}if let Some(Out::YArray(a))=m.get(&tx,"list"){let row=a.iter(&tx).find_map(|v|if let Out::YMap(m)=v{Some(m)}else{None});if let Some(row)=row{row.insert(&mut tx,"done",true);}if op[0]=="shift"{a.insert(&mut tx,0,n as i64);}else{let len=a.len(&tx);a.insert(&mut tx,len,n as i64);}}}},
 "xnew"=>{let p=n%(xmls[x].len(&tx)+1);let e=xmls[x].insert(&mut tx,p,yrs::XmlElementPrelim::empty("p"));e.insert_attribute(&mut tx,"class","entry");e.insert(&mut tx,0,yrs::XmlTextPrelim::new("hello"));},
 "xremove"=>{let len=xmls[x].len(&tx);if len>0{xmls[x].remove_range(&mut tx,n%len,1)}},
 "xedit"=>{let len=xmls[x].len(&tx);if len>0{let node=xmls[x].children(&tx).nth((n%len)as usize);if let Some(yrs::XmlOut::Element(e))=node{e.insert_attribute(&mut tx,"class",format!("c{n}"));let child=e.children(&tx).next();if let Some(yrs::XmlOut::Text(t))=child{t.insert_attribute(&mut tx,"lang","en");let p=n%(t.len(&tx)+1);t.insert(&mut tx,p,"!");}}}},
 _=>panic!("op")}
 }}
 let current:Vec<_>=docs.iter().enumerate().map(|(i,d)|{let tx=d.transact();json!({"map":roots[i].to_json(&tx),"xml":xmls[i].get_string(&tx),"xml_nodes":xmls[i].children(&tx).map(|n|xml_snapshot(n,&tx)).collect::<Vec<_>>(),"text":texts[i].get_string(&tx),"delta":texts[i].diff(&tx,yrs::types::text::YChange::identity).iter().map(|d|json!({"insert":d.insert.to_json(&tx),"attributes":d.attributes})).collect::<Vec<_>>()})}).collect();
 snapshots.push(json!({"docs":current,"notifications":*log.lock().unwrap(),"result":result,"stacks":managers.iter().map(|m|json!([m.undo_stack().len(),m.redo_stack().len()])).collect::<Vec<_>>()}));
 }
 if live {
 let updates:Vec<_>=docs.iter().map(|d|{let tx=d.transact();hex(&if v2{tx.encode_state_as_update_v2(&yrs::StateVector::default())}else{tx.encode_state_as_update_v1(&yrs::StateVector::default())})}).collect();println!("{}",json!({"snapshots":snapshots,"updates":updates}));io::stdout().flush().unwrap();snapshots.clear();
 match lines.next(){Some(line)=>{commands=serde_json::from_str(&line.unwrap()).unwrap();continue;},None=>break}
 } else { break; }
 }
 if !live {
 let updates:Vec<_>=docs.iter().map(|d|{let tx=d.transact();hex(&if v2{tx.encode_state_as_update_v2(&yrs::StateVector::default())}else{tx.encode_state_as_update_v1(&yrs::StateVector::default())})}).collect();println!("{}",json!({"snapshots":snapshots,"updates":updates}));
}
}}
