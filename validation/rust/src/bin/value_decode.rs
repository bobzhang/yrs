use serde_json::{json, Value};
use std::io::{self, BufRead};
use yrs::encoding::{read::Cursor, serde::from_any};
macro_rules! convert {
    ($value:expr, $ty:ty, $encode:expr) => {
        match from_any::<$ty>($value) {
            Ok(value) => json!({"ok":true,"value":($encode)(value)}),
            Err(_) => json!({"ok":false}),
        }
    };
}
macro_rules! cast {
    ($value:expr, $ty:ty, $encode:expr) => {
        match yrs::Out::Any($value.clone()).cast::<$ty>() {
            Ok(value) => json!({"ok":true,"value":($encode)(value)}),
            Err(original) => {
                assert_eq!(format!("{:?}", original), format!("{:?}", yrs::Out::Any($value.clone())));
                json!({"ok":false})
            }
        }
    };
}
fn main() {
    for line in io::stdin().lock().lines() {
        let input: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let bytes: Vec<u8> = serde_json::from_value(input[1].clone()).unwrap();
        let value = yrs::Any::decode(&mut Cursor::new(&bytes)).unwrap();
        let result = match input[0].as_str().unwrap() {
            "i64" => convert!(&value, i64, |n: i64| n.to_string()),
            "i32" => convert!(&value, i32, |n: i32| n.to_string()),
            "u32" => convert!(&value, u32, |n: u32| n.to_string()),
            "u64" => convert!(&value, u64, |n: u64| n.to_string()),
            "f64" => convert!(&value, f64, |n: f64| n.to_bits().to_string()),
            "f32" => convert!(&value, f32, |n: f32| n.to_bits().to_string()),
            "bool" => convert!(&value, bool, |n: bool| n),
            "string" => convert!(&value, String, |n: String| n),
            "optional" => convert!(&value, Option<i64>, |n: Option<i64>| n
                .map(|n| n.to_string())),
            "array" => convert!(&value, Vec<i64>, |n: Vec<i64>| n
                .into_iter()
                .map(|n| n.to_string())
                .collect::<Vec<_>>()),
            "cast/i64" => cast!(value, i64, |n: i64| n.to_string()),
            "cast/i32" => cast!(value, i32, |n: i32| n.to_string()),
            "cast/u32" => cast!(value, u32, |n: u32| n.to_string()),
            "cast/f64" => cast!(value, f64, |n: f64| n.to_bits().to_string()),
            "cast/f32" => cast!(value, f32, |n: f32| n.to_bits().to_string()),
            "cast/bool" => cast!(value, bool, |n: bool| n),
            "cast/string" => cast!(value, String, |n: String| n),
            "cast/bytes" => cast!(value, Vec<u8>, |n: Vec<u8>| n),
            _ => panic!("kind"),
        };
        println!("{}", result);
    }
}
