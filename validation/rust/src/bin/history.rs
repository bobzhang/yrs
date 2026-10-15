use std::io::{self,BufRead};
use serde_json::{json,Value};
use yrs::{Doc,Options,OffsetKind,Text,GetString,ReadTxn,Transact,IndexedSequence,StickyIndex,Assoc,Snapshot,Update,BranchID};
use yrs::updates::{decoder::Decode,encoder::Encode};
fn hex(b:&[u8])->String{b.iter().map(|b|format!("{b:02x}")).collect()}
fn unhex(s:&str)->Vec<u8>{(0..s.len()).step_by(2).map(|i|u8::from_str_radix(&s[i..i+2],16).unwrap()).collect()}
fn reference_snapshot_regression() {
 let mut options=Options::with_client_id(yrs::block::ClientID::new(1));options.skip_gc=true;
 let doc=Doc::with_options(options);let text=doc.get_or_insert_text("note");
 text.insert(&mut doc.transact_mut(),0,"ab");text.insert(&mut doc.transact_mut(),1,"X");
 let snapshot=doc.transact().snapshot();text.insert(&mut doc.transact_mut(),2,"Y");
 let mut encoder=yrs::updates::encoder::EncoderV1::new();
 doc.transact().encode_state_from_snapshot(&snapshot,&mut encoder).unwrap();
 let bytes=yrs::updates::encoder::Encoder::to_vec(encoder);
 println!("{}",json!({"wire":hex(&bytes),"reference_decode_error":format!("{:?}",Update::decode_v1(&bytes).unwrap_err())}));
}
fn main(){
 if std::env::args().any(|s|s=="--reference-snapshot-regression") { reference_snapshot_regression();return; }

 let v2=std::env::args().any(|s|s=="v2");
 for line in io::stdin().lock().lines(){
  let commands:Vec<Value>=serde_json::from_str(&line.unwrap()).unwrap();
  let docs:Vec<_>=(1..=3).map(|id|{let mut o=Options::with_client_id(yrs::block::ClientID::new(id));o.skip_gc=true;o.offset_kind=OffsetKind::Utf16;Doc::with_options(o)}).collect();
  let texts:Vec<_>=docs.iter().map(|d|d.get_or_insert_text("note")).collect();
  let mut marks:Vec<Option<StickyIndex>>=vec![];let mut saved:Vec<(usize,Snapshot,String)>=vec![];let mut snapshots=vec![];
  for c in commands{
   let x=c[1].as_u64().unwrap() as usize;
   match c[0].as_str().unwrap(){
    "i"=>{let mut tx=docs[x].transact_mut();let p=c[2].as_u64().unwrap() as u32%(texts[x].len(&tx)+1);texts[x].insert(&mut tx,p,c[3].as_str().unwrap())},
    "d"=>{let mut tx=docs[x].transact_mut();let n=texts[x].len(&tx);let p=c[2].as_u64().unwrap() as u32%(n+1);let len=c[3].as_u64().unwrap() as u32%(n-p+1);texts[x].remove_range(&mut tx,p,len)},
    "s"=>{let y=c[2].as_u64().unwrap() as usize;let tx=docs[x].transact();let sv=docs[y].transact().state_vector();let u=if v2{Update::decode_v2(&tx.encode_state_as_update_v2(&sv))}else{Update::decode_v1(&tx.encode_state_as_update_v1(&sv))}.unwrap();drop(tx);docs[y].transact_mut().apply_update(u).unwrap()},
    "mark"=>{let tx=docs[x].transact();let index=c[2].as_u64().unwrap() as u32%(texts[x].len(&tx)+2);let assoc=if c[3]==-1{Assoc::Before}else{Assoc::After};marks.push(texts[x].sticky_index(&tx,index,assoc))},
    "boundary"=>{let tx=docs[x].transact();marks.push(Some(StickyIndex::from_type(&tx,&texts[x],if c[2]==-1{Assoc::Before}else{Assoc::After})))},
    "snapshot"=>saved.push((x,docs[x].transact().snapshot(),texts[x].get_string(&docs[x].transact()))),
    "apply"=>{let b=unhex(c[2].as_str().unwrap());let u=if v2{Update::decode_v2(&b)}else{Update::decode_v1(&b)}.unwrap();docs[x].transact_mut().apply_update(u).unwrap()},
    "cursor_bytes"=>marks.push(Some(StickyIndex::decode_v1(&unhex(c[2].as_str().unwrap())).unwrap())),
    "snapshot_bytes"=>{let b=unhex(c[2].as_str().unwrap());saved.push((x,if v2{Snapshot::decode_v2(&b)}else{Snapshot::decode_v1(&b)}.unwrap(),c[3].as_str().unwrap().to_string()))},
    _=>panic!("operation")
   }
   let current:Vec<_>=texts.iter().zip(&docs).map(|(t,d)|t.get_string(&d.transact())).collect();
   let cursors:Vec<_>=marks.iter().map(|m|m.as_ref().map(|m|{
    let offsets:Vec<_>=docs.iter().map(|d|m.get_offset(&d.transact()).map(|o|{
     let branch=match o.branch.id(){BranchID::Root(name)=>json!(["root",name]),BranchID::Nested(id)=>json!(["nested",id.client.get(),id.clock])};json!([branch,o.index])
    })).collect();json!({"wire":hex(&m.encode_v1()),"json":serde_json::to_value(m).unwrap(),"offsets":offsets})
   })).collect();
   // Capture actual reference state when each snapshot is taken. The pinned
   // snapshot encoder can emit a HAS_RIGHT_ORIGIN flag without its ID when
   // clipping a block; see REFERENCE_LIMITATIONS.md. The MoonBit side must
   // reconstruct every historical value, without excluding these histories.
   let past:Vec<_>=saved.iter().map(|(_,_,text)|text.clone()).collect();
   let metadata:Vec<_>=saved.iter().map(|(_,snapshot,_)|{
    let mut state=snapshot.state_map.iter().map(|(id,clock)|(id.get(),*clock)).collect::<Vec<_>>();state.sort();
    let mut deleted=vec![];
    for (id,ranges) in snapshot.delete_set.iter(){for r in ranges.iter(){deleted.push((id.get(),r.start,r.end));}}deleted.sort();
    json!({"state":state,"deleted":deleted})
   }).collect();
   snapshots.push(json!({"text":current,"cursors":cursors,"past":past,"metadata":metadata}));
  }
  let updates:Vec<_>=docs.iter().map(|d|hex(&if v2{d.transact().encode_state_as_update_v2(&Default::default())}else{d.transact().encode_state_as_update_v1(&Default::default())})).collect();
  let saved:Vec<_>=saved.iter().map(|(d,s,text)|json!([d,hex(&if v2{s.encode_v2()}else{s.encode_v1()}),text])).collect();
  let marks:Vec<_>=marks.iter().filter_map(|m|m.as_ref().map(|m|hex(&m.encode_v1()))).collect();
  println!("{}",json!({"snapshots":snapshots,"updates":updates,"saved":saved,"marks":marks}));
 }
}
