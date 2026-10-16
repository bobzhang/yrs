use std::io::{self,BufRead};
use yrs::Update;
use yrs::updates::{decoder::Decode,encoder::Encode};
fn main(){for line in io::stdin().lock().lines(){
 let line=line.unwrap();let bytes:Vec<_>=(0..line.len()).step_by(2).map(|i|u8::from_str_radix(&line[i..i+2],16).unwrap()).collect();
 let encoded=Update::decode_v1(&bytes).unwrap().encode_v2();
 println!("{}",encoded.iter().map(|b|format!("{b:02x}")).collect::<String>());
}}
