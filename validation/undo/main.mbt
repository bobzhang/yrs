///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  @undo_core.evaluate(input)
}

///|
#export_name("evaluate_v2")
pub fn evaluate_v2(input : String) -> String {
  @undo_core.evaluate_v2(input)
}

///|
#export_name("evaluate_gc")
pub fn evaluate_gc(input : String, v2 : Bool) -> String {
  @undo_core.evaluate_gc(input, v2)
}

///|
#export_name("evaluate_live")
pub fn evaluate_live(input : String, v2 : Bool, gc : Bool) -> String {
  @undo_core.evaluate_live(input, v2, gc)
}
