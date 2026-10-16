#!/usr/bin/env python3
"""Every custom message tag and payload-length boundary through the Rust decoder."""
import json
from compare import ROOT, run
from updates import execute, varuint


def main():
    run(['cargo', '+1.97.1', 'build', '--release', '--locked', '--manifest-path',
         'validation/rust/Cargo.toml', '--bin', 'protocol_codec'])
    run(['moon', 'build', 'validation/protocol_codec', '--target', 'js', '--release'])
    cases = [[tag, [i % 256 for i in range(size)]]
             for tag in range(4, 256) for size in [0, 1, 127, 128, 255, 16384]]
    packets = execute(['node', 'validation/protocol_codec.cjs'], cases)
    reference = execute(['validation/rust/target/release/protocol_codec'], packets)
    encoder_differences = 0
    for (tag, payload), packet, decoded in zip(cases, packets, reference):
        expected = list(varuint(tag) + varuint(len(payload))) + payload
        assert packet == expected
        assert decoded['tag'] == tag and decoded['payload'] == payload
        if tag < 128:
            assert decoded['reference_encoding'] == packet
        else:
            # Pinned Rust writes a raw byte but reads a varuint tag.
            assert decoded['reference_encoding'] == [tag] + list(varuint(len(payload))) + payload
            assert decoded['reference_encoding'] != packet
            encoder_differences += 1
    result = {
        'upstream': 'ac339600c712642e556895426113c3f9c117de39',
        'custom_tags': 252, 'packets': len(cases),
        'rust_decoder_matches': len(cases),
        'reference_high_tag_encoder_differences': encoder_differences,
        'status': 'passed with explicit reference encoder exception',
    }
    (ROOT / 'validation/protocol-codec-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(result)


if __name__ == '__main__':
    main()
