use std::io::{self, BufRead};
use serde_json::{json, Value};
use yrs::{Any, ID, ClientID, updates::{encoder::{Encoder, EncoderV1, EncoderV2}, decoder::{Decoder, DecoderV1, DecoderV2}}, encoding::read::{Cursor, Error}};
use yrs::{types::{TypeRef, weak::LinkSource}, updates::{encoder::Encode, decoder::Decode}};
fn type_ref(value: &Value) -> TypeRef {
    match value["kind"].as_u64().unwrap() {
        0 => TypeRef::Array, 1 => TypeRef::Map, 2 => TypeRef::Text,
        3 => TypeRef::XmlElement(value["tag"].as_str().unwrap().into()),
        4 => TypeRef::XmlFragment, 5 => TypeRef::XmlHook, 6 => TypeRef::XmlText,
        7 => TypeRef::WeakLink(std::sync::Arc::new(LinkSource::new(
            serde_json::from_value(value["start"].clone()).unwrap(),
            serde_json::from_value(value["end"].clone()).unwrap()))),
        9 => TypeRef::SubDoc, 15 => TypeRef::Undefined, _ => panic!("type reference")
    }
}
fn bytes(value: &Value) -> Vec<u8> { value.as_array().unwrap().iter().map(|v| v.as_u64().unwrap() as u8).collect() }
fn encode<E: Encoder>(ops: &[Value], mut encoder: E) -> Vec<u8> {
    for op in ops {
        let kind = op[0].as_str().unwrap(); let v = &op[1];
        match kind {
            "reset" => encoder.reset_ds_cur_val(),
            "left" | "right" => { let id = ID::new(ClientID::new(v[0].as_str().unwrap().parse().unwrap()), v[1].as_u64().unwrap() as u32); if kind == "left" { encoder.write_left_id(&id) } else { encoder.write_right_id(&id) } }
            "client" => encoder.write_client(ClientID::new(v.as_str().unwrap().parse().unwrap())),
            "typevalue" => type_ref(v).encode(&mut encoder),
            "string" => encoder.write_string(v.as_str().unwrap()), "key" => encoder.write_key(v.as_str().unwrap()),
            "parent" => encoder.write_parent_info(v.as_bool().unwrap()),
            "any" | "json" => { let value = Any::from_json(&v.to_string()).unwrap(); if kind == "any" { encoder.write_any(&value) } else { encoder.write_json(&value) } }
            "all" => encoder.write_all(&bytes(v)), "buf" => encoder.write_buf(bytes(v)),
            _ => {
                let n = v.as_u64().unwrap() as u32;
                match kind {
                    "dsclock" => encoder.write_ds_clock(n), "dslen" => encoder.write_ds_len(n), "info" => encoder.write_info(n as u8), "type" => encoder.write_type_ref(n as u8), "len" => encoder.write_len(n),
                    "u8" => encoder.write_u8(n as u8), "u32" => encoder.write_u32(n), "var" => encoder.write_var(n), _ => panic!("kind")
                }
            }
        }
    }
    encoder.to_vec()
}
fn decode<D: Decoder>(ops: &[Value], mut decoder: D, raw: bool) -> Result<Value, Error> {
    if raw { return Ok(json!(decoder.read_to_end()?)); }
    let mut values = Vec::new();
    for op in ops {
        let value = match op[0].as_str().unwrap() {
            "reset" => { decoder.reset_ds_cur_val(); Value::Null }
            "left" | "right" => { let id = if op[0] == "left" { decoder.read_left_id()? } else { decoder.read_right_id()? }; json!([id.client.get().to_string(), id.clock]) }
            "client" => json!(decoder.read_client()?.get().to_string()), "string" => json!(decoder.read_string()?), "key" => json!(decoder.read_key()?.as_ref()),
            "parent" => json!(decoder.read_parent_info()?),
            "typevalue" => { let actual = TypeRef::decode(&mut decoder)?; json!({"kind": actual.kind(), "equal": actual == type_ref(&op[1])}) }
            "any" | "json" => { let value = if op[0] == "any" { decoder.read_any()? } else { decoder.read_json()? }; let mut s = String::new(); value.to_json(&mut s); serde_json::from_str(&s).unwrap() }
            "dsclock" => json!(decoder.read_ds_clock()?), "dslen" => json!(decoder.read_ds_len()?), "info" => json!(decoder.read_info()?), "type" => json!(decoder.read_type_ref()?), "len" => json!(decoder.read_len()?),
            "u8" => json!(decoder.read_u8()?), "u32" => json!(decoder.read_u32()?), "var" => json!(decoder.read_var::<u32>()?), _ => panic!("raw-only operation")
        }; values.push(value);
    }
    Ok(json!({"values": values, "tail": decoder.read_to_end()?}))
}
fn main() {
    for line in io::stdin().lock().lines() {
        let input: Value = serde_json::from_str(&line.unwrap()).unwrap(); let ops = input["ops"].as_array().unwrap(); let v2 = input["v2"].as_bool().unwrap(); let raw = input["raw"].as_bool().unwrap_or(false);
        let encoded = if v2 { encode(ops, EncoderV2::new()) } else { encode(ops, EncoderV1::new()) };
        let payload = input.get("bytes").map(bytes).unwrap_or_else(|| encoded.clone());
        let decoded = if v2 { DecoderV2::new(Cursor::new(&payload)).and_then(|d| decode(ops, d, raw)) } else { decode(ops, DecoderV1::from(payload.as_slice()), raw) }.unwrap_or(json!("error"));
        println!("{}", json!({"encoded": encoded, "decoded": decoded}));
    }
}
