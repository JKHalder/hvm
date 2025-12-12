# HVM3 (Zig)

A Zig implementation of [HVM3](https://github.com/HigherOrderCO/HVM3) - the Higher-Order Virtual Machine based on Interaction Calculus.

## Features

- Bit-packed 64-bit term representation for efficient memory usage
- All core interaction rules: APP-LAM, DUP-SUP, DUP-LAM, etc.
- Full arithmetic operators (+, -, *, /, %, ==, !=, <, >, &, |, ^, <<, >>)
- Superpositions and duplications for optimal sharing
- Parser for `.hvm` files
- ~13 MIPS (million interactions per second)

## Building

Requires Zig 0.15+:

```bash
zig build
```

## Usage

```bash
# Run an HVM file
./zig-out/bin/hvm3 run examples/test.hvm

# Evaluate an expression
./zig-out/bin/hvm3 eval "(+ #21 #21)"

# Run tests
./zig-out/bin/hvm3 test

# Run benchmarks
./zig-out/bin/hvm3 bench

# Show syntax examples
./zig-out/bin/hvm3 examples
```

## Syntax

| Syntax | Description | Example |
|--------|-------------|---------|
| `#N` | Number literal | `#42` |
| `'c'` | Character literal | `'x'` |
| `*` | Erasure | `*` |
| `\x.body` | Lambda | `\x.x` |
| `(f x)` | Application | `((\x.x) #42)` |
| `(op a b)` | Binary operation | `(+ #3 #4)` |
| `&L{a,b}` | Superposition | `&0{#1,#2}` |
| `!&L{x,y}=v;k` | Duplication | `!&0{a,b}=sup;a` |
| `(?n z s)` | Switch/match | `(?#0 #100 \p.#200)` |

## Example

```
// examples/test.hvm
(+ #21 #21)
```

```bash
$ ./zig-out/bin/hvm3 run examples/test.hvm
Result: #42
```

## License

MIT
