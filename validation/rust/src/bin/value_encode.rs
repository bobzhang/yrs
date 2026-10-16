use serde::{Serialize, Serializer};
use serde_json::{json, Value};
use std::{collections::HashMap, io::{self, BufRead}};
use yrs::{Any, Number, encoding::{read::Cursor, serde::to_any}};
#[derive(Serialize)]
struct Record { id: u64, title: String, flags: Vec<bool>, extra: Option<i64> }
struct Bytes(Vec<u8>);
impl Serialize for Bytes {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> { s.serialize_bytes(&self.0) }
}
fn view(value: Any) -> Value {
    match value {
        Any::Undefined => json!(["undefined"]), Any::Null => json!(["null"]),
        Any::Bool(v) => json!(["bool", v]), Any::Number(Number::Int(v)) => json!(["int", v.to_string()]),
        Any::Number(Number::Float(v)) => json!(["float", v.to_bits().to_string()]),
        Any::String(v) => json!(["string", v]), Any::Buffer(v) => json!(["buffer", v]),
        Any::Array(v) => json!(["array", v.iter().cloned().map(view).collect::<Vec<_>>()]),
        Any::Map(v) => json!(["object", v.iter().map(|(k,v)| (k.clone(),view(v.clone()))).collect::<serde_json::Map<_,_>>()]),
    }
}
fn uint(v: &Value) -> u64 { v.as_str().map(|s| s.parse().unwrap()).unwrap_or_else(|| v.as_u64().unwrap()) }
fn int(v: &Value) -> i64 { v.as_str().map(|s| s.parse().unwrap()).unwrap_or_else(|| v.as_i64().unwrap()) }
fn serialize<T: Serialize + ?Sized>(value: &T) -> Result<Any, String> { to_any(&value).map_err(|e| e.to_string()) }
fn convert(kind: &str, v: &Value) -> Result<Any, String> {
    match kind {
        "i64" => serialize(&int(v)), "i32" => serialize(&(int(v) as i32)),
        "u64" => serialize(&uint(v)), "u32" => serialize(&(uint(v) as u32)),
        "f64" => serialize(&f64::from_bits(uint(v))), "f32" => serialize(&f32::from_bits(uint(v) as u32)),
        "bool" => serialize(&v.as_bool().unwrap()), "string" => serialize(v.as_str().unwrap()),
        "unit" => serialize(&()), "optional" => serialize(&if v.is_null() { None } else { Some(uint(v)) }),
        "array" => serialize(&v.as_array().unwrap().iter().map(uint).collect::<Vec<_>>()),
        "map" => serialize(&v.as_object().unwrap().iter().map(|(k,v)| (k.clone(),uint(v))).collect::<HashMap<_,_>>()),
        "tuple" => serialize(&(v[0].as_str().unwrap(), uint(&v[1]))),
        "record" => serialize(&Record { id: uint(&v["id"]), title: v["title"].as_str().unwrap().to_string(), flags: serde_json::from_value(v["flags"].clone()).unwrap(), extra: if v["extra"].is_null() { None } else { Some(int(&v["extra"])) } }),
        "bytes" | "any" => { let bytes: Vec<u8> = serde_json::from_value(v.clone()).unwrap(); if kind == "bytes" { serialize(&Bytes(bytes)) } else { serialize(&Any::decode(&mut Cursor::new(&bytes)).unwrap()) } },
        _ => panic!("kind"),
    }
}
fn main() {
    for line in io::stdin().lock().lines() {
        let request: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let result = match convert(request[0].as_str().unwrap(), &request[1]) {
            Ok(value) => json!({"ok": true, "value": view(value)}),
            Err(_) => json!({"ok": false}),
        };
        println!("{}", result);
    }
}
