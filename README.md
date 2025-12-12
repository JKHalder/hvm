# HVM4 (Zig)

A Zig implementation of HVM4 - the Higher-Order Virtual Machine based on Interaction Calculus, with the new term layout, type system, and SupGen primitives.

## Features

- **HVM4 Architecture**: New 64-bit term layout `[8-bit tag][24-bit ext][32-bit val]`
- **50+ Term Types**: Constructors (C00-C15), primitives (P00-P15), stack frames, and more
- **17 Numeric Primitives**: ADD, SUB, MUL, DIV, MOD, AND, OR, XOR, LSH, RSH, NOT, EQ, NE, LT, LE, GT, GE
- **Optimal Duplication**: Label-based annihilation/commutation for optimal sharing
- **Stack Frame Evaluation**: Typed frames for WNF reduction (F_APP, F_MAT, F_SWI, F_OP2, etc.)
- **Lazy Collapse**: BFS enumeration of infinite superposition structures
- **Auto-Dup Foundation**: Variable use counting with label recycling
- **SIMD + Parallel**: Vectorized batch operations with multi-threaded execution
- **Parallel Reduction**: Work-stealing infrastructure for concurrent term reduction
- **Type System**: Annotations, structural equality, and type decay via interaction nets
- **SupGen Primitives**: Superposition-based program enumeration for discrete search
- **Safe-Level Analysis**: Static and runtime detection of oracle problem patterns
- **Configurable Runtime**: Adjustable heap, stack, workers, and optional reference counting

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
./zig-out/bin/hvm4 run examples/test.hvm

# Evaluate an expression
./zig-out/bin/hvm4 eval "(+ #21 #21)"

# Run tests
./zig-out/bin/hvm4 test

# Run parser tests
./zig-out/bin/hvm4 parse

# Run benchmarks
./zig-out/bin/hvm4 bench

# Show syntax examples
./zig-out/bin/hvm4 examples
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
| `{t : T}` | Type annotation | `{#42 : Type}` |
| `(=== a b)` | Structural equality | `(=== #42 #42)` |
| `@LOG(v k)` | Debug logging | `@LOG(#42 result)` |
| `Type` | Type universe | `Type` |

## Example

```
// examples/test.hvm
(+ #21 #21)
```

```bash
$ ./zig-out/bin/hvm4 eval "(+ #21 #21)"
#42

$ ./zig-out/bin/hvm4 eval "(* (+ #2 #3) (- #10 #4))"
#30
```

## Architecture

### Term Layout (HVM4)

```
64-bit term: [8-bit tag][24-bit ext][32-bit val]

- tag: Term type (0x00-0xFF)
- ext: Extension field (label, constructor ID, primitive ID)
- val: Value field (heap location or immediate value)
```

### Term Types

| Category | Tags | Description |
|----------|------|-------------|
| Core | APP, VAR, LAM, SUP, ERA, REF | Basic lambda calculus |
| Collapse | CO0, CO1 | Duplication projections |
| Constructors | C00-C15 | Arity 0-15 constructors |
| Primitives | P00-P15 | Arity 0-15 primitives |
| Pattern Match | MAT, SWI | Constructor and numeric matching |
| Stack Frames | F_APP, F_MAT, F_SWI, F_OP2, etc. | Evaluation frames |
| Special | DUP, LET, USE, EQL, RED | Advanced features |
| Type System | ANN, BRI, TYP, ALL, SIG, SLF | Type annotations and dependent types |

## Performance

Optimized following [VictorTaelin's IC techniques](https://gist.github.com/VictorTaelin/4f55a8a07be9bd9f6d828227675fa9ac):

- Cached heap/stack pointers in local variables
- Branch prediction hints (`@branchHint`) for hot paths
- Inlined critical interactions (APP-LAM, CO0/CO1-SUP, P02-NUM)
- Comptime dispatch table for interaction rules
- Stack frame-based WNF evaluation (no recursion)
- SIMD vectorized batch operations (4-wide vectors)
- Multi-threaded parallel execution (configurable workers)
- REF inline caching for hot function calls

### Interaction Net Benchmarks (Debug, Apple M4 Pro)

| Interaction | Ops/sec | Description |
|-------------|---------|-------------|
| DUP+NUM | ~29M | Trivial number duplication |
| MAT+CTR | ~23M | Pattern matching on constructors |
| CO0+SUP annihilation | ~21M | Same-label collapse (optimal) |
| Beta reduction | ~10-12M | APP+LAM interaction |
| DUP+LAM | ~11M | Lambda duplication |
| APP+SUP | ~9M | Superposition distribution |
| DUP+SUP commutation | ~8.5M | Different-label (creates 4 nodes) |
| DUP+CTR | ~6.3M | Constructor duplication |
| Deep nested β (depth=10) | ~14M | Stress test |

### SIMD Batch Benchmarks

| Benchmark | Ops/sec | Notes |
|-----------|---------|-------|
| Single-threaded arithmetic | ~19M | P02 binary primitives |
| SIMD batch add | ~360M | Vectorized, single-thread |
| SIMD batch multiply | ~665M | Vectorized, single-thread |
| **Parallel SIMD add** | ~850M | 12 threads |
| **Parallel SIMD multiply** | ~810M | 12 threads |

### API

```zig
const hvm = @import("hvm.zig");

// Configuration
const config = hvm.Config{
    .heap_size = 4 << 30,           // 4GB heap
    .stack_size = 1 << 26,          // 64MB stack
    .num_workers = 64,              // 64 threads
    .enable_refcount = true,        // Optional RC
    .enable_label_recycling = true, // Recycle labels
};
var state = try hvm.State.initWithConfig(allocator, config);

// SIMD batch operations
hvm.batch_add(a, b, results);
hvm.batch_mul(a, b, results);
hvm.parallel_batch_add(a, b, results);
hvm.parallel_batch_mul(a, b, results);

// Safety analysis (oracle problem detection)
const analysis = hvm.analyze_safety(term);
if (analysis.level == .unsafe) {
    // Handle potential exponential blowup
}

// Runtime monitoring
hvm.reset_commutation_counter();
_ = hvm.reduce(term);
if (hvm.commutation_limit_reached()) {
    // Too many DUP+SUP commutations
}

// Memory management
state.resetHeap();  // Arena-style reset
const stats = state.getStats();
```

Run benchmarks with:
```bash
./zig-out/bin/hvm4 bench
```

## References

- [HVM4 Technical Overview](https://gist.github.com/VictorTaelin/71e9b2ffeba3a9402afba76f8735d0b8)
- [HVM4 Commit History](https://gist.github.com/VictorTaelin/57d8082c7ffb97bd4755dd39815bd0cc)
- [IC Optimization to C](https://gist.github.com/VictorTaelin/ab20d7ec33ba7395ddacab58079fe20c)
- [VictorTaelin's X updates](https://x.com/VictorTaelin/status/1971591584916393984)

## License

MIT
