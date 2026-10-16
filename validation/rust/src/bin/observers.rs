//! Observer lifecycle reference assertions. No source changes to pinned Yrs.
use serde_json::json;
use std::sync::{Arc, Mutex};
use yrs::{Doc, Observable, Text, Transact};
fn main() {
    let mut phases = Vec::new();
    for phase in 0..5 {
        let doc = Doc::new();
        let text = doc.get_or_insert_text("text");
        let calls = Arc::new(Mutex::new(0u32));
        let mut tx = doc.transact_mut();
        for (me, other) in [("a", "b"), ("b", "a")] {
            let c = calls.clone();
            match phase {
                0 => tx.observe_before_observer_calls(me, move |tx| {
                    *c.lock().unwrap() += 1;
                    tx.unobserve_before_observer_calls(other);
                }),
                1 => tx.observe_after_transaction(me, move |tx| {
                    *c.lock().unwrap() += 1;
                    tx.unobserve_after_transaction(other);
                }),
                2 => tx.observe_transaction_cleanup(me, move |tx, _| {
                    *c.lock().unwrap() += 1;
                    tx.unobserve_transaction_cleanup(other);
                }),
                3 => tx.observe_update_v1(me, move |tx, _| {
                    *c.lock().unwrap() += 1;
                    tx.unobserve_update_v1(other);
                }),
                _ => tx.observe_update_v2(me, move |tx, _| {
                    *c.lock().unwrap() += 1;
                    tx.unobserve_update_v2(other);
                }),
            }
        }
        drop(tx);
        *calls.lock().unwrap() = 0;
        text.insert(&mut doc.transact_mut(), 0, "one");
        assert_eq!(*calls.lock().unwrap(), 2);
        text.insert(&mut doc.transact_mut(), 0, "two");
        assert_eq!(*calls.lock().unwrap(), 4);
        phases.push(json!({"phase":phase,"calls_after_two_edits":4}));
    }
    let doc = Doc::new();
    let text = doc.get_or_insert_text("text");
    let calls = Arc::new(Mutex::new(0u32));
    for (me, other) in [("a", "b"), ("b", "a")] {
        let c = calls.clone();
        let t = text.clone();
        text.observe(me, move |_, _| {
            *c.lock().unwrap() += 1;
            t.unobserve(other);
        });
    }
    text.insert(&mut doc.transact_mut(), 0, "x");
    assert_eq!(*calls.lock().unwrap(), 1);
    let pending_first = text.unobserve("a") || text.unobserve("b");
    let pending_repeat = text.unobserve("a") || text.unobserve("b");
    assert!(pending_first && pending_repeat);
    let destroyed = Doc::new();
    let destroy_calls = Arc::new(Mutex::new(0u32));
    let destroy_cancel = Arc::new(Mutex::new(Vec::new()));
    for (me, other) in [("a", "b"), ("b", "a")] {
        let c = destroy_calls.clone();
        let results = destroy_cancel.clone();
        destroyed
            .observe_destroy(me, move |tx, _| {
                *c.lock().unwrap() += 1;
                results.lock().unwrap().push(tx.unobserve_destroy(other));
            })
            .unwrap();
    }
    destroyed.destroy(None);
    println!(
        "{}",
        json!({"document_phases":phases,"typed_cancellation":true,"pending_repeat":pending_repeat,"destroy_calls":*destroy_calls.lock().unwrap(),"destroy_cancel":*destroy_cancel.lock().unwrap()})
    );
}
