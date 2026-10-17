///|
pub(all) enum ChangeKind {
  Added
  Removed
} derive(Eq, Debug)

///|
pub extend ChangeKind with Eq::{equal, not_equal}

///|
pub extend ChangeKind with Debug::{to_repr}

///|
pub(all) struct YChange {
  kind : ChangeKind
  id : Id
} derive(Eq, Debug)

///|
pub extend YChange with Eq::{equal, not_equal}

///|
pub extend YChange with Debug::{to_repr}

///|
pub fn YChange::identity(self : YChange) -> YChange {
  self
}

///|
pub(all) struct Diff[M] {
  insert : Out
  attributes : ReadOnlyArray[(String, Any)]
  ychange : M?
}

///|
priv struct DiffBuilder[M] {
  chunks : Array[Diff[M]]
  buffer : StringBuilder
  attributes : Map[String, Any]
  mut change : YChange?
  compute : (YChange) -> M
}

///|
fn[M] DiffBuilder::flush(self : DiffBuilder[M]) -> Unit {
  let text = self.buffer.to_string()
  if text != "" {
    self.chunks.push({
      insert: Value(String(text)),
      attributes: ReadOnlyArray::from_array(
        sorted_attributes(self.attributes)[:],
      ),
      ychange: self.change.map(self.compute),
    })
    self.buffer.reset()
    self.change = None
  }
}

///|
fn Snapshot::cuts(
  self : Snapshot,
  id : Id,
  end : UInt32,
  cuts : Set[UInt32],
) -> Unit {
  let clock = self.state.get(id.client)
  if id.clock < clock && clock < end {
    cuts.add(clock)
  }
  for (start, stop) in self.deletes.get(id.client).unwrap_or([]) {
    if id.clock < start && start < end {
      cuts.add(start)
    }
    if id.clock < stop && stop < end {
      cuts.add(stop)
    }
  }
}

///|
/// Rich-text content at a saved version, optionally annotated against an older
/// version. Deleted content must still be retained to reconstruct old versions.
pub fn[M] Text::diff_range(
  self : Text,
  compute_ychange : (YChange) -> M,
  hi? : Snapshot,
  lo? : Snapshot,
) -> Array[Diff[M]] {
  let builder : DiffBuilder[M] = {
    chunks: [],
    buffer: StringBuilder(),
    attributes: {},
    change: None,
    compute: compute_ychange,
  }
  let mut cursor = self.doc.branch(self.name).head
  while cursor is Some(id) {
    let item = self.doc.items[id]
    let end = id.clock + item.content.length().reinterpret_as_uint()
    let cuts = Set::from_array([id.clock, end])
    if hi is Some(snapshot) {
      snapshot.cuts(id, end, cuts)
    }
    if lo is Some(snapshot) {
      snapshot.cuts(id, end, cuts)
    }
    let cuts = cuts.to_array()
    cuts.sort()
    for i in 0..<(cuts.length() - 1) {
      let id : Id = { client: id.client, clock: cuts[i], }
      let high_visible = hi
        .map(fn(s) { s.is_visible(id) })
        .unwrap_or(!item.deleted)
      let low_visible = lo.map(fn(s) { s.is_visible(id) }).unwrap_or(false)
      if !high_visible && !low_visible {
        continue
      }
      match item.content {
        Characters(text) => {
          if hi is Some(_) {
            if !high_visible {
              builder.flush()
              builder.change = Some({ kind: Removed, id, })
            } else if lo is Some(_) {
              if !low_visible {
                builder.flush()
                builder.change = Some({ kind: Added, id, })
              } else if builder.change is Some(_) {
                builder.flush()
              }
            }
          }
          builder.buffer.write_string(
            text
            .slice(
              (cuts[i] - item.id.clock).reinterpret_as_int(),
              (cuts[i + 1] - item.id.clock).reinterpret_as_int(),
            )
            .text(),
          )
        }
        Shared(kind) => {
          builder.flush()
          builder.chunks.push({
            insert: self.doc.shared_output(item.id, kind),
            attributes: ReadOnlyArray::from_array(
              sorted_attributes(builder.attributes)[:],
            ),
            ychange: None,
          })
        }
        Embed(value) => {
          builder.flush()
          builder.chunks.push({
            insert: Value(value),
            attributes: ReadOnlyArray::from_array(
              sorted_attributes(builder.attributes)[:],
            ),
            ychange: None,
          })
        }
        Format(key, value) =>
          if high_visible {
            builder.flush()
            update_attribute(builder.attributes, key, value)
          }
        _ => ()
      }
    }
    cursor = item.right
  }
  builder.flush()
  builder.chunks
}

///|
pub fn[M] Text::diff(
  self : Text,
  compute_ychange : (YChange) -> M,
) -> Array[Diff[M]] {
  self.diff_range(compute_ychange)
}

///|
pub fn Text::push(self : Text, value : String) -> Unit {
  self.insert(self.length(), value)
}

///|
pub fn[M] XmlText::diff(
  self : XmlText,
  compute_ychange : (YChange) -> M,
) -> Array[Diff[M]] {
  self.as_text().diff(compute_ychange)
}

///|
pub fn[M] XmlText::diff_range(
  self : XmlText,
  compute_ychange : (YChange) -> M,
  hi? : Snapshot,
  lo? : Snapshot,
) -> Array[Diff[M]] {
  self.as_text().diff_range(compute_ychange, hi?, lo?)
}
