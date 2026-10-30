///|
fn main {
  guard @env.args() is [_, path] else {
    abort("usage: traces_native input.json")
  }
  println(@traces.evaluate(@utf8.decode_lossy(read_file(@utf8.encode(path)))))
}
