///|
fn main {
  let args = @env.args()
  guard args.length() == 2 else { abort("usage: traces_native input.json") }
  println(
    @traces.evaluate(@utf8.decode_lossy(read_file(@utf8.encode(args[1])))),
  )
}
