use serde_json::{json, Value};
use std::io::{self, BufRead};
use yrs::sync::Message;
use yrs::updates::{decoder::Decode, encoder::Encode};
fn main() {
    for line in io::stdin().lock().lines() {
        let input: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let bytes: Vec<u8> = serde_json::from_value(input).unwrap();
        let message = Message::decode_v1(&bytes).unwrap();
        match &message {
            Message::Custom(tag, payload) => println!(
                "{}",
                json!({
                    "tag": tag, "payload": payload, "reference_encoding": message.encode_v1()
                })
            ),
            _ => panic!("not custom"),
        }
    }
}
