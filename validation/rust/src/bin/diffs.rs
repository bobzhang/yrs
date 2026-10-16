use std::io::{self,BufRead};
use serde_json::{json,Value};
use yrs::{Doc,Options,ClientID,Text,Transact,ReadTxn,OffsetKind,Any,Update,StateVector,Snapshot};
use yrs::types::{ToJson,Attrs};
use yrs::types::text::YChange;
use yrs::updates::{encoder::Encode,decoder::Decode};
fn main(){for line in io::stdin().lock().lines(){let commands:Value=serde_json::from_str(&line.unwrap()).unwrap();let doc=Doc::with_options(Options{client_id:ClientID::new(1),skip_gc:true,cleanup_formatting:commands.get("cleanup").and_then(Value::as_bool).unwrap_or(false),offset_kind:OffsetKind::Utf16,..Options::default()});let text=doc.get_or_insert_text("text");let mut snapshots=Vec::new();let mut results=Vec::new();
if commands.is_object(){
 let packet:Vec<u8>=serde_json::from_value(commands["packet"].clone()).unwrap();doc.transact_mut().apply_update(Update::decode_v1(&packet).unwrap()).unwrap();
 let snap=|v:&Value|if v.is_null(){None}else{Some(Snapshot::decode_v1(&serde_json::from_value::<Vec<u8>>(v.clone()).unwrap()).unwrap())};
 let hi=snap(&commands["hi"]);let lo=snap(&commands["lo"]);
 let mut txn=doc.transact_mut();let chunks=text.diff_range(&mut txn,hi.as_ref(),lo.as_ref(),YChange::identity);
 println!("{}",json!(chunks.iter().map(|d|json!({"insert":d.insert.to_json(&txn),"attrs":d.attributes.as_deref().cloned().unwrap_or_default(),"change":d.ychange.as_ref().map(|c|json!([format!("{:?}",c.kind),c.id.client.get().to_string(),c.id.clock]))})).collect::<Vec<_>>()));continue;
}
for command in commands.as_array().unwrap(){match command[0].as_str().unwrap(){
 "i"=>{let at=command[1].as_u64().unwrap() as u32%(text.len(&doc.transact())+1);text.insert(&mut doc.transact_mut(),at,command[2].as_str().unwrap());},
 "d"|"f"=>{let len=text.len(&doc.transact());if len>0{let at=command[1].as_u64().unwrap() as u32%len;let n=(command[2].as_u64().unwrap() as u32).min(len-at);if command[0]=="d"{text.remove_range(&mut doc.transact_mut(),at,n);}else{let mut attrs=Attrs::new();attrs.insert("bold".into(),if command[3]==true{Any::Bool(true)}else{Any::Null});text.format(&mut doc.transact_mut(),at,n,attrs);}}},
 "e"=>{let at=command[1].as_u64().unwrap() as u32%(text.len(&doc.transact())+1);text.insert_embed(&mut doc.transact_mut(),at,Any::from(command[2].as_i64().unwrap()));},
 "s"=>snapshots.push(doc.transact().snapshot()),
 "q"=>{let h=command[1].as_i64().unwrap();let l=command[2].as_i64().unwrap();let hi=if h<0{None}else{Some(&snapshots[h as usize%snapshots.len()])};let lo=if l<0{None}else{Some(&snapshots[l as usize%snapshots.len()])};let mut txn=doc.transact_mut();
 results.push(json!({"packet":txn.encode_state_as_update_v1(&StateVector::default()),"hi":hi.map(|s|s.encode_v1()),"lo":lo.map(|s|s.encode_v1())}));
 text.diff_range(&mut txn,hi,lo,YChange::identity);
 },_=>panic!("command")}}
println!("{}",json!(results));}}
