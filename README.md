# HVM3 (Zig)

A Zig implementation of [HVM3](https://github.com/HigherOrderCO/HVM3) - the Higher-Order Virtual Machine based on Interaction Calculus.

## Features

- Bit-packed 64-bit term representation for efficient memory usage
- All core interaction rules: APP-LAM, DUP-SUP, DUP-LAM, etc.
- Full arithmetic operators (+, -, *, /, %, ==, !=, <, >, &, |, ^, <<, >>)
- Superpositions and duplications for optimal sharing
- Parser for `.hvm` files

## Building

Requires Zig 0.15+:

```bash
# Debug build (with safety checks)
zig build

# Release build (optimized for performance)
zig build -Doptimize=ReleaseFast
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

## Performance

The implementation is heavily optimized for speed with:
- Inlined hot paths and direct memory access
- Compile-time debug check removal in release builds
- SIMD vectorized batch operations
- Multi-threaded parallel execution (12 cores on M4 Pro)

### Benchmark Results (ReleaseFast, Apple M4 Pro)

| Benchmark | Ops/sec | Notes |
|-----------|---------|-------|
| Single-threaded arithmetic | 109M | Traditional reduce() |
| Beta reduction (λ application) | 145M | Traditional reduce() |
| DUP+SUP annihilation | 157M | Traditional reduce() |
| SIMD batch add | 1.4B | Vectorized, single-thread |
| SIMD batch multiply | 3.8B | Vectorized, single-thread |
| **Parallel SIMD add** | **13.9B** | **127x speedup** |
| **Parallel SIMD multiply** | **14.7B** | Multi-threaded + SIMD |

### Batch Operations API

For maximum performance on bulk numeric operations:

```zig
const hvm = @import("hvm.zig");

// SIMD batch operations (single-threaded)
hvm.batch_add(a, b, results);    // results[i] = a[i] + b[i]
hvm.batch_mul(a, b, results);    // results[i] = a[i] * b[i]
hvm.batch_sub(a, b, results);    // results[i] = a[i] - b[i]

// Parallel SIMD (multi-threaded, 12 cores)
hvm.parallel_batch_add(a, b, results);  // 127x faster than single-threaded
hvm.parallel_batch_mul(a, b, results);
```

Run benchmarks with:
```bash
./zig-out/bin/hvm3 bench
```

## License

MIT
