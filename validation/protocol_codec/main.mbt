///|
#export_name("evaluate")
pub fn evaluate(input : String) -> String {
  let data = try! @json.parse(input)
  guard data is Array([Number(tag, ..), Array(payload)]) else { abort("input") }
  let payload = Bytes::from_array(
    payload.map(fn(value) {
      guard value is Number(value, ..) else { abort("byte") }
      value.to_int().to_byte()
    }),
  )
  let message : @yrs.Message = Custom(tag.to_int().to_byte(), payload)
  let encoded = message.encode_v1()
  let decoded = try! @yrs.Message::decode_v1(encoded)
  guard decoded is Custom(decoded_tag, decoded_payload) else { abort("kind") }
  guard decoded_tag == tag.to_int().to_byte() && decoded_payload == payload else {
    abort("round trip")
  }
  Json(encoded.to_array().map(fn(byte) { Json(byte.to_int()) })).stringify()
}
