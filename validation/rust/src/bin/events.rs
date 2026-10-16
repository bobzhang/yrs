
use std::{io::{self,BufRead},sync::{Arc,Mutex}};
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
 Event::XmlFragment(e)=>{out["kind"]=json!("xml");out["delta"]=changes(e.delta(tx),tx);out["keys"]=keys(e.keys(tx),tx);out["children"]=json!(e.children_changed());
 let mut added=e.added(tx).iter().map(|id|(id.client.get(),id.clock)).collect::<Vec<_>>();added.sort();out["added"]=json!(added);
 let mut deleted=e.deleted(tx).iter().map(|id|(id.client.get(),id.clock)).collect::<Vec<_>>();deleted.sort();out["deleted"]=json!(deleted);},
 Event::XmlText(e)=>{out["kind"]=json!("xmltext");out["delta"]=delta(e.delta(tx),tx);out["keys"]=keys(e.keys(tx),tx);}
 }
 out
}
fn main(){let v2=std::env::args().any(|s|s=="v2");for line in io::stdin().lock().lines(){
 let commands:Vec<Value>=serde_json::from_str(&line.unwrap()).unwrap();
 let docs:Vec<_>=(1..=3).map(|i|{let mut o=Options::with_client_id(yrs::block::ClientID::new(i));o.skip_gc=true;o.offset_kind=OffsetKind::Utf16;Doc::with_options(o)}).collect();
 let roots:Vec<_>=docs.iter().map(|d|d.get_or_insert_map("root")).collect();let xmls:Vec<_>=docs.iter().map(|d|d.get_or_insert_xml_fragment("xml")).collect();
 let log=Arc::new(Mutex::new(vec![]));
 for i in 0..3{let l=log.clone();roots[i].observe_deep("deep",move|tx,es|{l.lock().unwrap().push(json!({"doc":i,"scope":"map","events":es.iter().map(|e|event(e,tx)).collect::<Vec<_>>()}));});
 let l=log.clone();xmls[i].observe_deep("deep",move|tx,es|{l.lock().unwrap().push(json!({"doc":i,"scope":"xml","events":es.iter().map(|e|event(e,tx)).collect::<Vec<_>>()}));});
 let l=log.clone();xmls[i].observe("shallow",move|tx,e|{l.lock().unwrap().push(json!({"doc":i,"scope":"shallow","delta":changes(e.delta(tx),tx),"keys":keys(e.keys(tx),tx),"children":e.children_changed()}));});}
 let mut snapshots=vec![];
 for command in commands{log.lock().unwrap().clear();let x=command[1].as_u64().unwrap() as usize;
 if command[0]=="sync"{let y=command[2].as_u64().unwrap() as usize;let sv=docs[y].transact().state_vector();let tx=docs[x].transact();let u=if v2{Update::decode_v2(&tx.encode_state_as_update_v2(&sv))}else{Update::decode_v1(&tx.encode_state_as_update_v1(&sv))}.unwrap();drop(tx);docs[y].transact_mut().apply_update(u).unwrap();}
 else{let mut tx=docs[x].transact_mut();for op in command[2].as_array().unwrap(){let n=op[1].as_u64().unwrap() as u32;let key=format!("key{}",n%3);
 match op[0].as_str().unwrap(){
 "new"=>{let m=roots[x].insert(&mut tx,key.as_str(),yrs::MapPrelim::default());m.insert(&mut tx,"title",yrs::TextPrelim::new("hello"));let a=m.insert(&mut tx,"list",yrs::ArrayPrelim::default());let row=a.insert(&mut tx,0,yrs::MapPrelim::default());row.insert(&mut tx,"done",false);},
 "remove"=>{roots[x].remove(&mut tx,&key);},
 "edit"|"shift"=>{if let Some(Out::YMap(m))=roots[x].get(&tx,&key){if let Some(Out::YText(t))=m.get(&tx,"title"){let p=n%(t.len(&tx)+1);t.insert(&mut tx,p,"!");}if let Some(Out::YArray(a))=m.get(&tx,"list"){let row=a.iter(&tx).find_map(|v|if let Out::YMap(m)=v{Some(m)}else{None});if let Some(row)=row{row.insert(&mut tx,"done",true);}if op[0]=="shift"{a.insert(&mut tx,0,n as i64);}else{let len=a.len(&tx);a.insert(&mut tx,len,n as i64);}}}},
 "xnew"=>{let p=n%(xmls[x].len(&tx)+1);let e=xmls[x].insert(&mut tx,p,yrs::XmlElementPrelim::empty("p"));e.insert_attribute(&mut tx,"class","entry");e.insert(&mut tx,0,yrs::XmlTextPrelim::new("hello"));},
 "xremove"=>{let len=xmls[x].len(&tx);if len>0{xmls[x].remove_range(&mut tx,n%len,1)}},
 "xedit"=>{let len=xmls[x].len(&tx);if len>0{let node=xmls[x].children(&tx).nth((n%len)as usize);if let Some(yrs::XmlOut::Element(e))=node{e.insert_attribute(&mut tx,"class",format!("c{n}"));let child=e.children(&tx).next();if let Some(yrs::XmlOut::Text(t))=child{t.insert_attribute(&mut tx,"lang","en");let p=n%(t.len(&tx)+1);t.insert(&mut tx,p,"!");}}}},
 _=>panic!("op")}
 }}
 let current:Vec<_>=docs.iter().enumerate().map(|(i,d)|{let tx=d.transact();json!({"map":roots[i].to_json(&tx),"xml":xmls[i].get_string(&tx)})}).collect();
 snapshots.push(json!({"docs":current,"notifications":*log.lock().unwrap()}));
 }
 println!("{}",json!({"snapshots":snapshots}));
}}
