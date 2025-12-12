# HVM4 Demos

This folder contains demonstrations of HVM4's capabilities. Each file showcases a different aspect of the Higher-Order Virtual Machine.

## Running Demos

```bash
# Build HVM4
zig build -Doptimize=ReleaseFast

# Run a demo
./zig-out/bin/hvm4 demo/arithmetic.hvm

# Run all demos
for f in demo/*.hvm; do echo "=== $f ===" && ./zig-out/bin/hvm4 "$f"; done

# Run benchmarks (includes GPU tests)
./zig-out/bin/hvm4 bench
```

## Demos (24 total)

### Core Language Features

| Demo | Result | Description |
|------|--------|-------------|
| `arithmetic.hvm` | `#42` | Math, bitwise, and comparison operations |
| `identity.hvm` | `#42` | Identity function and higher-order functions |
| `combinators.hvm` | `#42` | SKI combinator calculus (Turing-complete basis) |
| `logging.hvm` | `LOG: #42` → `#100` | Debug logging with @LOG |

### Lambda Calculus Encodings

| Demo | Result | Description |
|------|--------|-------------|
| `church.hvm` | `#2` | Church numerals - numbers as lambda functions |
| `booleans.hvm` | `#1` | Church booleans - if-then-else as functions |
| `lists.hvm` | `#1` | Church-encoded linked lists |
| `scott-encoding.hvm` | `#1` | Scott encoding for O(1) pattern matching |
| `bitstring.hvm` | `#0` | Binary numbers as nested lambdas |

### Recursion & Fixed Points

| Demo | Result | Description |
|------|--------|-------------|
| `fibonacci.hvm` | `#100` | Fibonacci using numeric switch |
| `factorial.hvm` | `#4` | Factorial and predecessor operations |
| `y-combinator.hvm` | `#42` | Y combinator and fixed-point recursion |

### HVM4's Unique Features

| Demo | Result | Description |
|------|--------|-------------|
| `superposition.hvm` | `&0{#1,#2}` | **Automatic parallelism** - HVM4's killer feature |
| `duplication.hvm` | `#84` | **Optimal sharing** - O(1) annihilation |
| `parallel-computation.hvm` | `#84` | Massive parallelism demonstration |
| `gpu-acceleration.hvm` | `#42` | **Metal GPU** - 22-70x speedup |
| `optimal-reduction.hvm` | `#42` | **Exponential speedup** via sharing |

### Type System

| Demo | Result | Description |
|------|--------|-------------|
| `types.hvm` | `#42` | Type annotations with `{term : Type}` |
| `structural-equality.hvm` | `#1` | Deep equality with `(=== a b)` |

### Advanced Computation

| Demo | Result | Description |
|------|--------|-------------|
| `parallel-search.hvm` | `&0{#0,#1}` | **SAT-like parallel search** using superposition |
| `lambda-calculus.hvm` | `#0` | **Meta-circular evaluator** - interpreter in itself |
| `binary-tree.hvm` | `#3` | **Parallel tree operations** - automatic parallelism |
| `turing-machine.hvm` | `#0` | **Universal computation** - Turing completeness proof |
| `derivative.hvm` | `#7` | **Symbolic differentiation** - autodiff foundation |

## Syntax Quick Reference

```
#42          Number literal
'x'          Character (as number)
*            Erasure (unused value)
\x.body      Lambda abstraction
(f x y)      Function application
(+ a b)      Binary operation (+, -, *, /, %, &, |, ^, <<, >>, ==, !=, <, >, <=, >=)
&L{a, b}     Superposition with label L (PARALLEL BRANCHES!)
!&L{x,y}=v;k Duplication binding (OPTIMAL SHARING!)
(?n z s)     Numeric switch (if n=0 then z else s(n-1))
{t : T}      Type annotation
(=== a b)    Structural equality
@LOG(v k)    Debug logging
// comment   Line comment
```

## What Makes HVM4 Special

### 1. Automatic Parallelism
```
&{a, b}  →  Both branches evaluated IN PARALLEL
```
No threads, no locks, no coordination. Just write `&{...}` and HVM4 handles parallelism automatically.

### 2. Optimal Reduction
```
Same-label DUP+SUP  →  O(1) annihilation (not copying!)
```
Some programs that take exponential time in normal lambda calculus run in polynomial time on HVM4.

### 3. Metal GPU Acceleration
```
GPU batch operations  →  22-70x speedup
```
Automatic GPU dispatch for batch operations on Apple Silicon.

### 4. Lock-Free Concurrency
```
Atomic operations  →  Safe parallel reduction
```
Work-stealing schedulers distribute load across all CPU cores.

## Performance (Apple M4 Pro)

| Feature | Performance |
|---------|-------------|
| Serial beta reduction | ~140M ops/sec |
| Parallel reduction | ~42B ops/sec (**310x** speedup) |
| GPU batch add | 3.1B ops/sec (22x) |
| GPU batch mul | 9.8B ops/sec (70x) |
| GPU heap transfer | 1.7B terms/sec |

## Demo Highlights

### Parallel Search (`parallel-search.hvm`)
Use superposition to explore ALL possibilities simultaneously:
```
x = &{0, 1}
y = &{0, 1}
f(x, y)  →  All 4 combinations computed IN PARALLEL!
```

### Optimal Reduction (`optimal-reduction.hvm`)
Programs with sharing get exponential speedups:
```
Tower(n) in normal lambda calculus: O(2^n) steps
Tower(n) in HVM4: O(n) interactions!
```

### Binary Trees (`binary-tree.hvm`)
Tree operations naturally parallelize:
```
sum(Node(left, right)) = sum(left) + sum(right)
                         ↑           ↑
                   PARALLEL     PARALLEL
```

## Learn More

See the main [README.md](../README.md) for full documentation and benchmarks.
