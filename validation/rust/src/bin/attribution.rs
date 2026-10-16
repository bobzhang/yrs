use std::io::{self,BufRead};
use serde_json::{json,Value};
use yrs::{IdMap,ContentAttribute,AttrRange,IdSet,ID,ClientID,Diff};
use yrs::block::BlockRange;
use yrs::updates::{encoder::Encode,decoder::Decode};
fn n(v:&Value)->u64 {v.as_u64().unwrap()}
fn range(v:&Value)->BlockRange {BlockRange{client:ClientID::new(n(&v[0])),clock:n(&v[1]) as u32,len:n(&v[2]) as u32}}
fn attrs(v:&Value)->Vec<ContentAttribute<String>> {v.as_array().unwrap().iter().map(|p|ContentAttribute::new(p[0].as_str().unwrap(),p[1].as_str().unwrap().to_string())).collect()}
fn rjson(r:AttrRange<String>)->Value {json!([r.range.start,r.range.end,r.attrs.iter().map(|a|json!([a.name(),a.value()])).collect::<Vec<_>>()])}
fn report(m:&IdMap<String>)->Value {json!({"ranges":m.iter().map(|(c,r)|json!([c.get().to_string(),rjson(r)])).collect::<Vec<_>>(),"v1":m.encode_v1(),"v2":m.encode_v2(),"set":m.as_id_set().encode_v1(),"empty":m.is_empty(),"query":m.attributions(&BlockRange{client:ClientID::new(1),clock:0,len:120}).into_iter().map(rjson).collect::<Vec<_>>()})}
fn main(){for line in io::stdin().lock().lines(){let input:Value=serde_json::from_str(&line.unwrap()).unwrap();
 if input.get("range").is_some() {
  let r=range(&input["range"]);let s=r.slice(n(&input["offset"]) as u32);let clocks=r.clock_range();
  let id=|v:ID|json!([v.client.get().to_string(),v.clock]);
  let contains:Vec<_>=input["ids"].as_array().unwrap().iter().map(|v|r.contains(&ID::new(ClientID::new(n(&v[0])),n(&v[1]) as u32))).collect();
  println!("{}",json!({"id":id(r.id()),"last":id(r.last_id()),"end":r.clock_end(),"clocks":[clocks.start,clocks.end],"slice":[s.clock,s.len],"contains":contains}));continue;
 }
 let mut maps=vec![IdMap::<String>::new();3];let mut rows=vec![];
 for op in input.as_array().unwrap(){let x=n(&op[1]) as usize;match op[0].as_str().unwrap(){
 "insert"=>maps[x].insert(range(&op[2]),attrs(&op[3])),
 "remove"=>maps[x].remove(&range(&op[2])),
 "merge"=>{let other=maps[n(&op[2]) as usize].clone();maps[x].merge_with(other)},
 "intersect"=>{let other=maps[n(&op[2]) as usize].clone();maps[x].intersect_with(&other)},
 "diff"=>{let other=maps[n(&op[2]) as usize].clone();maps[x].diff_with(&other)},
 "filter"=>{let name=op[2].as_str().unwrap();maps[x]=maps[x].filter(|a|a.iter().any(|v|v.name()==name));},
 "from"=>{let r=range(&op[2]);let mut s=IdSet::new();s.insert(ID::new(r.client,r.clock),r.len);maps[x]=IdMap::from_set(s,attrs(&op[3]));},
 "reload1"=>maps[x]=IdMap::decode_v1(&maps[x].encode_v1()).unwrap(),
 "reload2"=>maps[x]=IdMap::decode_v2(&maps[x].encode_v2()).unwrap(),
 "load1"=>maps[x]=IdMap::decode_v1(&serde_json::from_value::<Vec<u8>>(op[2].clone()).unwrap()).unwrap(),
 "load2"=>maps[x]=IdMap::decode_v2(&serde_json::from_value::<Vec<u8>>(op[2].clone()).unwrap()).unwrap(),
 _=>panic!("command")};rows.push(report(&maps[x]));}
 println!("{}",json!(rows));}}
