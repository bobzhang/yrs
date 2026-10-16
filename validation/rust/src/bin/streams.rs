use std::io::{self, BufRead};
use serde_json::{json, Value};
use yrs::encoding::{read::{Read, Cursor}, write::Write, varint::Signed};
fn encode(ops: &[Value]) -> Vec<u8> {
    let mut out = Vec::new();
    for op in ops {
        let kind = op[0].as_str().unwrap(); let v = &op[1];
        match kind {
            "string" => out.write_string(v.as_str().unwrap()),
            "buf" => out.write_buf(v.as_array().unwrap().iter().map(|v| v.as_u64().unwrap() as u8).collect::<Vec<_>>()),
            "i64" | "varint" | "signed" => {
                let n: i64 = v.as_str().unwrap().parse().unwrap();
                match kind { "i64" => out.write_i64(n), "varint" => out.write_var(n), _ => out.write_var_signed(&Signed::new(n, n <= 0)) }
            }
            _ => {
                let n: u64 = v.as_str().unwrap().parse().unwrap();
                match kind {
                    "u8" => out.write_u8(n as u8), "u16" => out.write_u16(n as u16), "u32" => out.write_u32(n as u32),
                    "u32be" => out.write_u32_be(n as u32), "u64" => out.write_u64(n), "varuint" => out.write_var(n),
                    "f32" => out.write_f32(f32::from_bits(n as u32)), "f64" => out.write_f64(f64::from_bits(n)), _ => panic!("kind")
                }
            }
        }
    }
    out
}
fn decode(ops: &[Value], bytes: &[u8]) -> Result<Value, yrs::encoding::read::Error> {
    let mut reader = Cursor::new(bytes); let mut values = Vec::new();
    for op in ops {
        let value = match op[0].as_str().unwrap() {
            "string" => json!(reader.read_string()?), "buf" => json!(reader.read_buf()?),
            "u8" => json!(reader.read_u8()?.to_string()), "u16" => json!(reader.read_u16()?.to_string()),
            "u32" => json!(reader.read_u32()?.to_string()), "u32be" => json!(reader.read_u32_be()?.to_string()),
            "u64" => json!(reader.read_u64()?.to_string()), "i64" => json!(reader.read_i64()?.to_string()),
            "varuint" => json!(reader.read_var::<u64>()?.to_string()), "varint" => json!(reader.read_var::<i64>()?.to_string()),
            "signed" => { let n = reader.read_var_signed::<i64>()?; json!([n.value().to_string(), n.is_negative()]) },
            "f32" => json!(reader.read_f32()?.to_bits().to_string()), "f64" => json!(reader.read_f64()?.to_bits().to_string()),
            _ => panic!("kind")
        }; values.push(value);
    }
    Ok(json!({"values": values, "position": reader.next, "remaining": bytes.len() - reader.next}))
}
fn main() {
    for line in io::stdin().lock().lines() {
        let input: Value = serde_json::from_str(&line.unwrap()).unwrap(); let ops = input["ops"].as_array().unwrap();
        let encoded = encode(ops);
        let bytes = input.get("bytes").map(|v| v.as_array().unwrap().iter().map(|v| v.as_u64().unwrap() as u8).collect::<Vec<_>>()).unwrap_or_else(|| encoded.clone());
        let decoded = decode(ops, &bytes).unwrap_or(json!("error"));
        println!("{}", json!({"encoded": encoded, "decoded": decoded}));
    }
}
