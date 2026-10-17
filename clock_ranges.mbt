///|
// Maintain canonical sorted, disjoint, non-adjacent ranges in place, as Rust's
// IdRanges does. Appending or extending the last range needs no history scan.
fn insert_clock_range(
  ranges : Array[(UInt32, UInt32)],
  start : UInt32,
  end : UInt32,
) -> Unit {
  guard start < end else { return }
  if ranges.last() is Some((a, b)) && start >= a {
    if start > b {
      ranges.push((start, end))
    } else {
      ranges[ranges.length() - 1] = (a, b.max(end))
    }
    return
  }
  let first = for lo = 0, hi = ranges.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    if ranges[mid].1 < start {
      continue mid + 1, hi
    } else {
      continue lo, mid
    }
  } nobreak {
    lo
  }
  let mut last = first
  let mut low = start
  let mut high = end
  while last < ranges.length() && ranges[last].0 <= high {
    low = low.min(ranges[last].0)
    high = high.max(ranges[last].1)
    last += 1
  }
  if first == last {
    ranges.insert(first, (low, high))
  } else {
    ranges[first] = (low, high)
    let removed = last - first - 1
    if removed > 0 {
      for i in last..<ranges.length() {
        ranges[i - removed] = ranges[i]
      }
      ranges.truncate(ranges.length() - removed)
    }
  }
}
