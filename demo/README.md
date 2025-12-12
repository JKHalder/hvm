# HVM4 Demos

This folder contains demonstrations of HVM4's capabilities. Each file showcases a different aspect of the Higher-Order Virtual Machine.

## Running Demos

```bash
# Build HVM4
zig build -Doptimize=ReleaseFast

# Run a demo
./zig-out/bin/hvm4 demo/arithmetic.hvm
```

## Demos

### Core Language Features

| Demo | Description |
|------|-------------|
| `arithmetic.hvm` | Basic math, bitwise, and comparison operations |
| `identity.hvm` | Identity function and higher-order functions |
| `combinators.hvm` | SKI combinator calculus (Turing-complete basis) |

### Lambda Calculus Encodings

| Demo | Description |
|------|-------------|
| `church.hvm` | Church numerals - numbers as lambda functions |
| `booleans.hvm` | Church booleans - if-then-else as functions |
| `lists.hvm` | Church-encoded linked lists |

### Recursion

| Demo | Description |
|------|-------------|
| `fibonacci.hvm` | Fibonacci using numeric switch |
| `factorial.hvm` | Factorial and predecessor operations |

### HVM4's Unique Features

| Demo | Description |
|------|-------------|
| `superposition.hvm` | **Automatic parallelism** - HVM4's killer feature |
| `duplication.hvm` | **Optimal sharing** - O(1) annihilation |
| `parallel-computation.hvm` | Massive parallelism demonstration |

## Syntax Quick Reference

```
#42          Number literal
'x'          Character (as number)
*            Erasure (unused value)
\x.body      Lambda abstraction
(f x y)      Function application
(+ a b)      Binary operation (+, -, *, /, %, &, |, ^, <<, >>, ==, !=, <, >, <=, >=)
&L{a, b}     Superposition with label L
!&L{x,y}=v;k Duplication binding
(?n z s)     Numeric switch (if n=0 then z else s(n-1))
{t : T}      Type annotation
// comment   Line comment
```

## What Makes HVM4 Special

1. **Automatic Parallelism**: Superposition `&{a, b}` evaluates both branches in parallel automatically
2. **Optimal Reduction**: Same-label DUP+SUP pairs annihilate in O(1) time
3. **310x Speedup**: Achieves massive parallelism without explicit threading
4. **Lock-Free**: Atomic operations enable safe concurrent reduction
5. **SIMD-Optimized**: SoA memory layout enables vectorized operations

## Learn More

See the main [README.md](../README.md) for full documentation and benchmarks.
