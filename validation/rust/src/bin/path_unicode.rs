use serde_json::json;
fn ranges(predicate:fn(char)->bool)->Vec<(u32,u32)>{let mut result=Vec::new();let mut start=None;for i in 0..=0x110000{let yes=char::from_u32(i).map(predicate).unwrap_or(false);match(start,yes){(None,true)=>start=Some(i),(Some(a),false)=>{result.push((a,i));start=None},_=>()}}result}
fn main(){println!("{}",json!({"unicode":char::UNICODE_VERSION,"alphabetic":ranges(char::is_alphabetic),"numeric":ranges(char::is_numeric)}));}
