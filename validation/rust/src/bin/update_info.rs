use std::io::{self,BufRead};
use serde_json::{json,Value};
use yrs::{Update,StateVector,ClientID,IdSet};
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
fn vector(s:&StateVector)->Value {let mut pairs=s.iter().map(|(c,n)|json!([c.get().to_string(),n])).collect::<Vec<_>>();pairs.sort_by_key(|v|v[0].as_str().unwrap().parse::<u64>().unwrap());json!(pairs)}
fn ranges(s:IdSet)->Value {json!(s.iter().flat_map(|(c,rs)|rs.iter().map(move |r|json!([c.get().to_string(),r.start,r.end]))).collect::<Vec<_>>())}
fn main(){for line in io::stdin().lock().lines(){let request:Value=serde_json::from_str(&line.unwrap()).unwrap();if request.is_object(){
 let sticky:yrs::StickyIndex=serde_json::from_value(request["sticky"].clone()).unwrap();
 let vector=StateVector::from_iter([(ClientID::new(request["client"].as_u64().unwrap()),request["clock"].as_u64().unwrap() as u32)]);
 println!("{}",json!({"sticky":sticky.encode_v2(),"vector":vector.encode_v2()}));continue;
}let hex=request[0].as_str().unwrap();let bytes:Vec<_>=(0..hex.len()).step_by(2).map(|i|u8::from_str_radix(&hex[i..i+2],16).unwrap()).collect();let update=Update::decode_v1(&bytes).unwrap();let state=StateVector::from_iter(request[1].as_array().unwrap().iter().map(|p|(ClientID::new(p[0].as_u64().unwrap()),p[1].as_u64().unwrap() as u32)));println!("{}",json!({"empty":update.is_empty(),"extends":update.extends(&state),"state":vector(&update.state_vector()),"lower":vector(&update.state_vector_lower()),"live":ranges(update.insertions(false)),"all":ranges(update.insertions(true)),"deleted":ranges(update.delete_set().clone())}));}}
