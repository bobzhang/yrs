#!/usr/bin/env python3
"""Primitive/shared text embeds, inherited marks and explicit replacements."""
import random
from compare import main


def scenarios():
    cases = [[['trace', 0], ['t', 0, 0, 'abc', {'bold': True}],
              ['embed', 0, 1, 'value', 'atomic string', None],
              ['embed', 0, 2, 'map', 17, {}],
              ['embed', 0, 3, 'array', True, {'italic': True}],
              ['embed', 0, 4, 'text', 'nested', None], ['s', 0, 1]]]
    for seed in range(32):
        rng = random.Random(44000+seed)
        commands = [['trace', 0], ['t', 0, 0, 'initial text', {'bold': True}]]
        for _ in range(120):
            op = rng.choice(['embed']*4 + ['f', 't', 'i', 'd', 'd', 's', 'q', 'r'])
            x, at = rng.randrange(3), rng.randrange(1000)
            if op == 'embed':
                kind = rng.choice(['value', 'map', 'array', 'text'])
                value = rng.choice(['one', '界', 'nested']) if kind == 'text' else rng.choice(
                    [None, True, 42, 'atomic', {'image': 'moon.png'}, [1, 2]])
                command = [op, x, at, kind, value,
                           rng.choice([None, {}, {'bold': True}, {'italic': True}])]
            elif op == 'f':
                command = [op, x, at, rng.randrange(20), {'bold': rng.choice([True, None])}]
            elif op == 't':
                command = [op, x, at, 'marked', {'bold': True}]
            elif op == 'i':
                command = [op, x, at, 'plain']
            elif op == 'd':
                command = [op, x, at, rng.randrange(20)]
            elif op in ['s', 'q']:
                command = [op, x, (x+rng.randrange(1, 3)) % 3]
            else:
                command = [op, at]
            commands.append(command)
        for _ in range(3):
            commands.extend(['s', x, y] for x in range(3) for y in range(3) if x != y)
        cases.append(commands)
    return cases


if __name__ == '__main__':
    main(scenarios(), 'embed-results.json')
