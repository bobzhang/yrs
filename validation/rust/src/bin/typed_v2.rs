use std::io::{self, BufRead};
use yrs::{Any, Doc, Out, ReadTxn, Text, Transact, Update};
use yrs::updates::decoder::Decode;
fn hex(b: &[u8]) -> String { b.iter().map(|b| format!("{b:02x}")).collect() }
fn unhex(s: &str) -> Vec<u8> { (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i+2], 16).unwrap()).collect() }
fn main() {
    for line in io::stdin().lock().lines() {
        let packets: Vec<String> = serde_json::from_str(&line.unwrap()).unwrap();
        let values = [Any::Buffer(vec![1u8,2].into()), Any::Undefined, Any::from(9007199254740993i64)];
        let mut output = vec![];
        for (i, value) in values.into_iter().enumerate() {
            let doc = Doc::with_client_id(1);
            let text = doc.get_or_insert_text("text");
            if packets.is_empty() {
                let mut tx = doc.transact_mut();
                text.insert_embed(&mut tx, 0, value.clone());
                text.insert_with_attributes(&mut tx, 1, "x", [("custom".into(), value.clone())].into());
            } else {
                doc.transact_mut().apply_update(Update::decode_v2(&unhex(&packets[i])).unwrap()).unwrap();
            }
            let tx = doc.transact();
            let delta = text.diff(&tx, |_| ());
            assert_eq!(delta.len(), 2);
            assert_eq!(delta[0].insert, Out::Any(value.clone()));
            assert_eq!(delta[1].attributes.as_ref().unwrap().get("custom"), Some(&value));
            output.push(hex(&tx.encode_state_as_update_v2(&Default::default())));
        }
        println!("{}", serde_json::to_string(&output).unwrap());
    }
}
