use serde_json::{json, Value};
use std::sync::{Arc, Mutex};
use yrs::updates::decoder::Decode;
use yrs::{
    ClientID, Doc, GetString, OffsetKind, Options, ReadTxn, StateVector, Text, Transact, Update,
};
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
fn unhex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let input: Value = serde_json::from_str(&std::fs::read_to_string(&args[1]).unwrap()).unwrap();
    let gc = input["gc"].as_bool().unwrap_or(false);
    let doc = Doc::with_options(Options {
        client_id: ClientID::new(1),
        skip_gc: !gc,
        offset_kind: OffsetKind::Utf16,
        ..Options::default()
    });
    let text = doc.get_or_insert_text("text");
    if let Some(wire) = input["wire"].as_str() {
        let data = unhex(wire);
        let update = if input["v2"].as_bool().unwrap_or(false) {
            Update::decode_v2(&data)
        } else {
            Update::decode_v1(&data)
        }
        .unwrap();
        doc.transact_mut().apply_update(update).unwrap();
        println!("{}", text.get_string(&doc.transact()));
        return;
    }
    let follower = Doc::with_options(Options {
        client_id: ClientID::new(2),
        skip_gc: !gc,
        offset_kind: OffsetKind::Utf16,
        ..Options::default()
    });
    let peer_text = follower.get_or_insert_text("text");
    let queue = Arc::new(Mutex::new(Vec::<Vec<u8>>::new()));
    let capture = queue.clone();
    doc.observe_update_v1("network", move |_, e| {
        capture.lock().unwrap().push(e.update.clone());
    })
    .unwrap();
    let txns = input["txns"].as_array().unwrap();
    let mut patches = 0;
    let mut packets = 0;
    let mut checkpoints = 0;
    let mut catchups = 0;
    for (i, txn) in txns.iter().enumerate() {
        {
            let mut tx = doc.transact_mut();
            for change in txn.as_array().unwrap() {
                let at = change[0].as_u64().unwrap() as u32;
                let count = change[1].as_u64().unwrap() as u32;
                let value = change[2].as_str().unwrap();
                if count > 0 {
                    text.remove_range(&mut tx, at, count);
                }
                if !value.is_empty() {
                    text.insert(&mut tx, at, value);
                }
                patches += 1;
            }
        }
        if (i + 1) % 128 == 0 || i + 1 == txns.len() {
            while let Some(bytes) = queue.lock().unwrap().pop() {
                for _ in 0..2 {
                    follower
                        .transact_mut()
                        .apply_update(Update::decode_v1(&bytes).unwrap())
                        .unwrap();
                    packets += 1;
                }
            }
            if text.get_string(&doc.transact()) != peer_text.get_string(&follower.transact())
                || doc.transact().state_vector() != follower.transact().state_vector()
            {
                let full = doc
                    .transact()
                    .encode_state_as_update_v1(&StateVector::default());
                follower
                    .transact_mut()
                    .apply_update(Update::decode_v1(&full).unwrap())
                    .unwrap();
                catchups += 1;
            }
            assert_eq!(
                text.get_string(&doc.transact()),
                peer_text.get_string(&follower.transact()),
                "reconnect at {i}"
            );
            assert_eq!(
                doc.transact().state_vector(),
                follower.transact().state_vector()
            );
            checkpoints += 1;
        }
    }
    let tx = doc.transact();
    let wire_v1 = tx.encode_state_as_update_v1(&StateVector::default());
    let wire_v2 = tx.encode_state_as_update_v2(&StateVector::default());
    for version in 1..=2 {
        let peer = Doc::with_client_id(3);
        peer.transact_mut()
            .apply_update(
                if version == 1 {
                    Update::decode_v1(&wire_v1)
                } else {
                    Update::decode_v2(&wire_v2)
                }
                .unwrap(),
            )
            .unwrap();
        assert_eq!(
            peer.get_or_insert_text("text").get_string(&peer.transact()),
            text.get_string(&tx)
        );
    }
    println!(
        "{}",
        json!({"text":text.get_string(&tx),"clock":tx.state_vector().get(&ClientID::new(1)),"patches":patches,"transactions":txns.len(),"deliveries":packets,"checkpoints":checkpoints,"catchups":catchups,"wire_v1":hex(&wire_v1),"wire_v2":hex(&wire_v2)})
    );
}
