///|
pub fn BlockRange::id(self : BlockRange) -> Id {
  { client: self.client, clock: self.clock, }
}

///|
/// The exclusive upper clock, matching the pinned Yrs method despite its name.
pub fn BlockRange::last_id(self : BlockRange) -> Id {
  { client: self.client, clock: self.end(), }
}

///|
pub fn BlockRange::clock_end(self : BlockRange) -> UInt32 {
  self.end()
}

///|
/// Half-open clock interval represented as (start, end).
pub fn BlockRange::clock_range(self : BlockRange) -> (UInt32, UInt32) {
  (self.clock, self.end())
}

///|
/// Drop offset clocks from the beginning. An offset equal to length is valid
/// and produces an empty range; larger offsets are rejected.
pub fn BlockRange::slice(self : BlockRange, offset : UInt32) -> BlockRange {
  guard offset <= self.length else { abort("block range slice out of bounds") }
  self.end() |> ignore
  BlockRange(self.client, self.clock + offset, self.length - offset)
}

///|
pub fn BlockRange::contains(self : BlockRange, id : Id) -> Bool {
  self.client == id.client && self.clock <= id.clock && id.clock < self.end()
}
