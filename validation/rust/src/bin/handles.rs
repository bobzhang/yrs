use serde_json::{json, Value};
use std::io::{self, BufRead};
use yrs::updates::decoder::Decode;
use yrs::{
    ClientID, Doc, GetString, Hook, Map, MapRef, OffsetKind, Options, ReadTxn, Root, SharedRef,
    StateVector, TextPrelim, Transact, Update,
};
fn serialized<S>(hook: &Hook<S>) -> Value {
    serde_json::to_value(Hook::<()>::from(hook.id().clone())).unwrap()
}
fn main() {
    for line in io::stdin().lock().lines() {
        let input: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let client = input[0].as_u64().unwrap();
        let name = input[1].as_str().unwrap();
        let gc = input[2].as_bool().unwrap();
        let doc = Doc::with_options(Options {
            client_id: ClientID::new(client),
            skip_gc: !gc,
            offset_kind: OffsetKind::Utf16,
            ..Options::default()
        });
        let root: Root<MapRef> = Root::new(name);
        assert!(root.get(&doc.transact()).is_none());
        let map = root.get_or_create(&mut doc.transact_mut());
        let text = map.insert(&mut doc.transact_mut(), "note", TextPrelim::new("Moon🌙"));
        let root_hook = map.hook();
        let nested_hook = text.hook();
        let nested = nested_hook.clone().into_nested().unwrap();
        let peer = Doc::with_client_id(client + 1);
        peer.transact_mut()
            .apply_update(
                Update::decode_v2(
                    &doc.transact()
                        .encode_state_as_update_v2(&StateVector::default()),
                )
                .unwrap(),
            )
            .unwrap();
        let remote = nested_hook
            .get(&peer.transact())
            .unwrap()
            .get_string(&peer.transact());
        assert_eq!(
            nested
                .get(&peer.transact())
                .unwrap()
                .get_string(&peer.transact()),
            remote
        );
        map.remove(&mut doc.transact_mut(), "note");
        let replacement = map.insert(&mut doc.transact_mut(), "note", TextPrelim::new("new"));
        peer.transact_mut()
            .apply_update(
                Update::decode_v1(
                    &doc.transact()
                        .encode_state_as_update_v1(&StateVector::default()),
                )
                .unwrap(),
            )
            .unwrap();
        let encoded = serialized(&nested_hook);
        let decoded: Hook<()> = serde_json::from_value(encoded.clone()).unwrap();
        assert_eq!(decoded.id(), nested_hook.id());
        println!(
            "{}",
            json!({"root":serialized(&root_hook),"nested":encoded,"replacement":serialized(&replacement.hook()),"before":remote,"after":replacement.hook().get(&peer.transact()).unwrap().get_string(&peer.transact()),"old_missing":nested_hook.get(&doc.transact()).is_none() && nested_hook.get(&peer.transact()).is_none(),"root_present":root.get(&peer.transact()).is_some(),"nested_json_without_tag_accepted":serde_json::from_value::<Hook<()>>(json!({"id":nested_hook.id()})).is_ok()})
        );
    }
}
