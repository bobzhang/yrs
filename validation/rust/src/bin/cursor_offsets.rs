use serde_json::{json, Value};
use std::io::{self, BufRead};
use yrs::updates::decoder::Decode;
use yrs::{
    Assoc, ClientID, Doc, GetString, IndexedSequence, OffsetKind, Options, ReadTxn, StateVector,
    Text, Transact, Update,
};
fn main() {
    for line in io::stdin().lock().lines() {
        let r: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let a = Doc::with_options(Options {
            client_id: ClientID::new(1),
            offset_kind: OffsetKind::Utf16,
            skip_gc: true,
            ..Options::default()
        });
        let b = Doc::with_options(Options {
            client_id: ClientID::new(2),
            offset_kind: OffsetKind::Bytes,
            skip_gc: true,
            ..Options::default()
        });
        let text = a.get_or_insert_text("text");
        let bytes = b.get_or_insert_text("text");
        text.insert(&mut a.transact_mut(), 0, r[0].as_str().unwrap());
        b.transact_mut()
            .apply_update(
                Update::decode_v1(
                    &a.transact()
                        .encode_state_as_update_v1(&StateVector::default()),
                )
                .unwrap(),
            )
            .unwrap();
        let assoc = if r[3].as_bool().unwrap() {
            Assoc::Before
        } else {
            Assoc::After
        };
        let left = text.sticky_index(&mut a.transact_mut(), r[1].as_u64().unwrap() as u32, assoc);
        let right = bytes.sticky_index(&mut b.transact_mut(), r[2].as_u64().unwrap() as u32, assoc);
        let mut rows = vec![];
        for _ in 0..4 {
            rows.push(
                json!({"text":text.get_string(&a.transact()),"utf":left,"bytes":right,
   "utf_offset":left.as_ref().and_then(|s|s.get_offset(&a.transact())).map(|o|o.index),
   "byte_offset":left.as_ref().and_then(|s|s.get_offset(&b.transact())).map(|o|o.index),
   "byte_own_offset":right.as_ref().and_then(|s|s.get_offset(&b.transact())).map(|o|o.index)}),
            );
            text.insert(&mut a.transact_mut(), 0, "é🦀");
            b.transact_mut()
                .apply_update(
                    Update::decode_v2(
                        &a.transact()
                            .encode_state_as_update_v2(&StateVector::default()),
                    )
                    .unwrap(),
                )
                .unwrap();
        }
        println!("{}", json!(rows));
    }
}
