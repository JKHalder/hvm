# HVM4 Upgrade Plan

Based on research from [VictorTaelin's gists](https://gist.github.com/VictorTaelin) and [X posts](https://x.com/VictorTaelin/status/1971591584916393984), this document outlines the plan to upgrade our HVM3 Zig implementation to HVM4.

## Key Differences: HVM3 vs HVM4

| Feature | HVM3 (Current) | HVM4 (Target) |
|---------|----------------|---------------|
| Term size | 64-bit (1-7-16-40 layout) | 64-bit (8-24-32 layout) |
| Term types | 19 tags | 50+ tags |
| Duplication | Manual | Auto-dup system |
| Stack frames | Untyped terms | Named frame types |
| Type system | None | Native type checking |
| Collapse | Eager | Lazy (BFS) |
| Primitives | As operators | First-class term types |

## Phase 1: Term Representation (Priority: High)

### 1.1 New 64-bit Layout
```
Current HVM3:  [1-bit sub][7-bit tag][16-bit lab][40-bit loc]
Target HVM4:   [8-bit tag][24-bit ext][32-bit val]
```

**Changes needed in `hvm.zig`:**
```zig
// New constants
const TAG_BITS: u6 = 8;
const EXT_BITS: u6 = 24;
const VAL_BITS: u6 = 32;

const TAG_MASK: u64 = 0xFF00000000000000;
const EXT_MASK: u64 = 0x00FFFFFF00000000;
const VAL_MASK: u64 = 0x00000000FFFFFFFF;

const TAG_SHIFT: u6 = 56;
const EXT_SHIFT: u6 = 32;
const VAL_SHIFT: u6 = 0;
```

### 1.2 New Term Types
```zig
// Core types (hot path - positions 0-7)
pub const APP: Tag = 0x00;  // Application
pub const VAR: Tag = 0x01;  // Variable
pub const LAM: Tag = 0x02;  // Lambda
pub const CO0: Tag = 0x03;  // Dup branch 0 (replaces DP0)
pub const CO1: Tag = 0x04;  // Dup branch 1 (replaces DP1)
pub const SUP: Tag = 0x05;  // Superposition
pub const DUP: Tag = 0x06;  // Duplication node
pub const ALO: Tag = 0x07;  // Book-level variables

// Additional types
pub const ERA: Tag = 0x08;  // Erasure
pub const RED: Tag = 0x09;  // Guarded reduction (f ~> g)
pub const NUM: Tag = 0x1E;  // 32-bit number (replaces W32)
pub const MAT: Tag = 0x1F;  // Constructor pattern match
pub const SWI: Tag = 0x20;  // Numeric pattern match
pub const USE: Tag = 0x21;  // Strict evaluation
pub const EQL: Tag = 0x22;  // Structural equality

// Constructors C00-C16 (arity 0-16)
pub const C00: Tag = 0x0D;
pub const C01: Tag = 0x0E;
// ... up to C16

// Primitives P00-P16 (arity 0-16)
pub const P00: Tag = 0x22;
pub const P01: Tag = 0x23;
// ... up to P16

// Dynamic sup/dup
pub const DSU: Tag = 0x33;  // Dynamic superposition
pub const DDU: Tag = 0x34;  // Dynamic duplication
```

## Phase 2: WNF Evaluator with Stack Frames (Priority: High)

### 2.1 Stack Frame Types
```zig
// Stack frame tags (0x40+)
pub const F_APP_RED: Tag = 0x40;  // Reducing function in guarded app
pub const F_RED_MAT: Tag = 0x41;  // Reducing arg for pattern match
pub const F_RED_SWI: Tag = 0x42;  // Reducing arg for numeric switch
pub const F_RED_USE: Tag = 0x43;  // Reducing arg for strict eval
pub const F_OP2_NUM: Tag = 0x44;  // Reducing second numeric operand
```

### 2.2 Evaluation Protocol
1. **Enter phase**: Push stack frames, follow heap references
2. **Apply phase**: Pop frames, execute interaction rules
3. Support recursive re-entry via `base_stack_pos` tracking

### 2.3 Updated Interaction Rules

| Interaction | HVM3 | HVM4 |
|-------------|------|------|
| APP + LAM | reduce_app_lam | Beta reduction (same) |
| APP + RED | N/A | Guarded application |
| DUP + term | reduce_dup_* | Clone with CO0/CO1 refs |
| SUP + term | reduce_*_sup | Branch superposition |
| MAT + CTR | reduce_mat_ctr | Constructor matching |
| SWI + NUM | reduce_mat_w32 | Numeric switching |

## Phase 3: Auto-Dup System (Priority: Medium)

### 3.1 Variable Affinity
- Non-cloned variables: used exactly 0 or 1 time
- Cloned variables (`&x`): unlimited uses

### 3.2 Auto-Dup Transformation
```
Input:  λx.[x,x,x]
Output: λx.!d0&=x; !d1&=d0₁; [d0₀,d1₀,d1₁]
```

### 3.3 Implementation Steps
1. Count variable uses in term
2. Insert N-1 dups for N uses
3. Replace VAR refs with CO0/CO1 refs
4. Shift De Bruijn indices for outer-scope variables

### 3.4 Fresh Label Namespace
Auto-generated labels start at `0x800000` (2^23) to avoid collision.

## Phase 4: New Primitives (Priority: Medium)

### 4.1 Numeric Primitives (17 total)
```zig
// Arithmetic
pub const PRM_ADD: Lab = 0x00;
pub const PRM_SUB: Lab = 0x01;
pub const PRM_MUL: Lab = 0x02;
pub const PRM_DIV: Lab = 0x03;
pub const PRM_MOD: Lab = 0x04;

// Bitwise
pub const PRM_AND: Lab = 0x05;
pub const PRM_OR:  Lab = 0x06;
pub const PRM_XOR: Lab = 0x07;
pub const PRM_LSH: Lab = 0x08;
pub const PRM_RSH: Lab = 0x09;
pub const PRM_NOT: Lab = 0x0A;

// Comparison (return 0/1)
pub const PRM_EQ:  Lab = 0x0B;
pub const PRM_NE:  Lab = 0x0C;
pub const PRM_LT:  Lab = 0x0D;
pub const PRM_LE:  Lab = 0x0E;
pub const PRM_GT:  Lab = 0x0F;
pub const PRM_GE:  Lab = 0x10;
```

### 4.2 Structural Equality (EQL)
- `===` operator for arbitrary term comparison
- Returns `#1` if equal, `#0` otherwise
- Handles SUP/ERA propagation

## Phase 5: Lazy Collapse (Priority: Low)

### 5.1 collapse_step()
- Single-step SUP lifting instead of eager collapse
- Enables BFS enumeration of infinite terms
- Example: `@X = &L{#Z, #S{@X}}` enumeration

### 5.2 Implementation
```zig
pub fn collapse_step(term: Term) ?Term {
    // Return next step or null if fully collapsed
}

pub fn collapse_iter() CollapseIterator {
    // BFS iterator over superposition branches
}
```

## Phase 6: Parser Updates (Priority: Low)

### 6.1 New Syntax
- Fork notation: `&Lλx,y,z{A;B}`
- Optional separators: `&L{A B}` or `&L{A,B}`
- Multi-arg lambda: `λx,y,z.f`
- Lambda-dup: `λx&L.F`
- Dynamic sup/dup: `&(L){A,B}`, `!x&(L)=v;b`

### 6.2 Operator Precedence
```
Lowest:  || (logical or)
         &&
         |, ^, &
         ==, !=, <, <=, >, >=
         <<, >>
         +, -
Highest: *, /, %
```

## Implementation Order

1. **Week 1-2**: Term representation changes (Phase 1)
   - Update bit layout
   - Add new term types
   - Update term_new, term_tag, term_ext, term_val

2. **Week 3-4**: WNF evaluator (Phase 2)
   - Add stack frame types
   - Rewrite reduce() with new interaction rules
   - Add CO0/CO1 handling

3. **Week 5-6**: Auto-dup system (Phase 3)
   - Implement variable counting
   - Add dup insertion
   - Update parser

4. **Week 7-8**: Primitives and features (Phase 4-5)
   - Add new primitives
   - Implement lazy collapse
   - Add structural equality

5. **Week 9-10**: Parser and polish (Phase 6)
   - New syntax support
   - Testing and benchmarks
   - Documentation

## Performance Targets

Based on [VictorTaelin's benchmarks](https://x.com/VictorTaelin/status/1994370663516115444):

| Metric | HVM3 | HVM4 Target |
|--------|------|-------------|
| Interactions/sec | 160M | 190M |
| Memory efficiency | Good | Better (32-bit val) |
| Parallelism | Basic | Full GPU support |

## Files to Modify

1. `src/hvm.zig` - Core VM (major changes)
2. `src/parser.zig` - Parser (syntax additions)
3. `src/main.zig` - CLI (new commands)
4. `build.zig` - Build config (GPU support later)

## References

- [HVM4 Technical Overview](https://gist.github.com/VictorTaelin/71e9b2ffeba3a9402afba76f8735d0b8)
- [HVM4 Commit History](https://gist.github.com/VictorTaelin/57d8082c7ffb97bd4755dd39815bd0cc)
- [IC Optimization to C](https://gist.github.com/VictorTaelin/ab20d7ec33ba7395ddacab58079fe20c)
- [VictorTaelin's X updates](https://x.com/VictorTaelin/status/1971591584916393984)
