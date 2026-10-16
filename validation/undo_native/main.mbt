///|
extern "c" fn read_line() -> Bytes = "yrs_undo_read_line"

///|
extern "c" fn flush_output() -> Unit = "yrs_undo_flush_output"

///|
fn main {
  let args = @env.args()
  let v2 = args.contains("v2")
  let gc = args.contains("--gc")
  let live = args.contains("--live")
  for ;; {
    let bytes = read_line()
    if bytes.is_empty() {
      break
    }
    let input = @utf8.decode_lossy(bytes)
    let output = if live {
      @undo_core.evaluate_live(input, v2, gc)
    } else if gc {
      @undo_core.evaluate_gc(input, v2)
    } else if v2 {
      @undo_core.evaluate_v2(input)
    } else {
      @undo_core.evaluate(input)
    }
    println(output)
    flush_output()
  }
}
