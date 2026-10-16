#!/usr/bin/env python3
"""XML preliminary copies and attribute conversion against pinned Rust."""
import random
from compare import main


def scenarios():
    cases = []
    for seed in range(32):
        rng = random.Random(51000+seed)
        commands = [['x', 0, 0, 'p', 'initial']]
        for _ in range(80):
            op = rng.choice(['xmlattr']*4 + ['copyxml', 'x', 'X', 's', 'q', 'r'])
            x, at = rng.randrange(3), rng.randrange(1000)
            if op == 'xmlattr':
                command = [op, x, at, rng.choice(['element', 'text']),
                           rng.choice(['count', 'title', 'active']),
                           rng.choice([None, True, False, -42, 1.5, '界', ['a', 3]])]
            elif op == 'copyxml':
                command = [op, x, at]
            elif op == 'x':
                command = [op, x, at, 'p', 'copyable']
            elif op == 'X':
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
    main(scenarios(), 'prelim-results.json')
