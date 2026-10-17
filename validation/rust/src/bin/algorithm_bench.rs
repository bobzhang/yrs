use yrs::{Array, ClientID, Doc, GetString, OffsetKind, Options, ReadTxn, StateVector, Text, Transact, Update};
use yrs::updates::decoder::Decode;
fn uint(out: &mut Vec<u8>, mut value: u64) {
    while value >= 128 { out.push(value as u8 | 128); value >>= 7; }
    out.push(value as u8);
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let kind = &args[1];
    let size: u32 = args[2].parse().unwrap();
    let doc = Doc::with_options(Options { client_id: ClientID::new(1000000), skip_gc: true, offset_kind: OffsetKind::Utf16, ..Options::default() });
    let text = doc.get_or_insert_text("text");
    let array = doc.get_or_insert_array("array");
    match kind.as_str() {
        "text" => for i in 0..size { text.insert(&mut doc.transact_mut(), i, "x"); },
        "array" => for i in 0..size { array.insert_range(&mut doc.transact_mut(), i, [i as i64]); },
        "dependencies" => {
            let mut wire = vec![];
            uint(&mut wire, size as u64);
            for i in (1..=size).rev() {
                uint(&mut wire, 1); uint(&mut wire, i as u64); uint(&mut wire, 0);
                if i == 1 { wire.extend_from_slice(&[4, 1, 4, b't', b'e', b'x', b't']); }
                else { wire.push(132); uint(&mut wire, (i - 1) as u64); uint(&mut wire, 0); }
                wire.extend_from_slice(&[1, b'x']);
            }
            wire.push(0);
            doc.transact_mut().apply_update(Update::decode_v1(&wire).unwrap()).unwrap();
        },
        _ => panic!("unknown workload")
    }
    let txn = doc.transact();
    let length = if kind == "array" { array.len(&txn) } else { text.len(&txn) };
    assert_eq!(length, size);
    if kind == "array" {
        for i in 0..size { assert_eq!(array.get(&txn, i), Some(yrs::Out::Any((i as i64).into()))); }
    } else { assert!(text.get_string(&txn).chars().all(|c| c == 'x')); }
    let v1 = txn.encode_state_as_update_v1(&StateVector::default());
    let v2 = txn.encode_state_as_update_v2(&StateVector::default());
    println!("{}", serde_json::json!({"length": length, "v1_bytes": v1.len(), "v2_bytes": v2.len()}));
}
