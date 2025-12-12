// =============================================================================
// HVM4 Metal Compute Shaders
// GPU-accelerated interaction rule processing
// =============================================================================

#include <metal_stdlib>
using namespace metal;

// =============================================================================
// Term Layout: [8-bit tag][24-bit ext][32-bit val]
// =============================================================================

typedef uint64_t Term;
typedef uint8_t Tag;
typedef uint32_t Ext;  // Actually 24-bit, stored in 32
typedef uint32_t Val;

// Bit manipulation constants
constant uint64_t TAG_SHIFT = 56;
constant uint64_t EXT_SHIFT = 32;
constant uint64_t TAG_MASK = 0xFF00000000000000ULL;
constant uint64_t EXT_MASK = 0x00FFFFFF00000000ULL;
constant uint64_t VAL_MASK = 0x00000000FFFFFFFFULL;
constant uint64_t SUB_BIT  = 0x8000000000000000ULL;

// Tag constants (must match hvm.zig)
constant Tag APP = 0x00;
constant Tag VAR = 0x01;
constant Tag LAM = 0x02;
constant Tag CO0 = 0x03;
constant Tag CO1 = 0x04;
constant Tag SUP = 0x05;
constant Tag DUP = 0x06;
constant Tag REF = 0x07;
constant Tag ERA = 0x08;
constant Tag NUM = 0x22;
constant Tag P02 = 0x32;

// Operator constants
constant Ext OP_ADD = 0x00;
constant Ext OP_SUB = 0x01;
constant Ext OP_MUL = 0x02;
constant Ext OP_DIV = 0x03;
constant Ext OP_MOD = 0x04;
constant Ext OP_AND = 0x05;
constant Ext OP_OR  = 0x06;
constant Ext OP_XOR = 0x07;
constant Ext OP_LSH = 0x08;
constant Ext OP_RSH = 0x09;
constant Ext OP_EQ  = 0x0B;
constant Ext OP_NE  = 0x0C;
constant Ext OP_LT  = 0x0D;
constant Ext OP_LE  = 0x0E;
constant Ext OP_GT  = 0x0F;
constant Ext OP_GE  = 0x10;

// =============================================================================
// Term manipulation functions
// =============================================================================

inline Tag term_tag(Term t) {
    return (Tag)((t >> TAG_SHIFT) & 0xFF);
}

inline Ext term_ext(Term t) {
    return (Ext)((t >> EXT_SHIFT) & 0xFFFFFF);
}

inline Val term_val(Term t) {
    return (Val)(t & VAL_MASK);
}

inline Term term_new(Tag tag, Ext ext, Val val) {
    return ((uint64_t)tag << TAG_SHIFT) | ((uint64_t)(ext & 0xFFFFFF) << EXT_SHIFT) | (uint64_t)val;
}

inline Term term_set_sub(Term t) {
    return t | SUB_BIT;
}

inline bool term_is_sub(Term t) {
    return (t & SUB_BIT) != 0;
}

// Follow substitution chain
inline Term deref(device Term* heap, Term t) {
    while (term_is_sub(t)) {
        t = heap[term_val(t)];
    }
    return t;
}

// =============================================================================
// Arithmetic operations
// =============================================================================

inline uint32_t compute_op(Ext op, uint32_t a, uint32_t b) {
    switch (op) {
        case OP_ADD: return a + b;
        case OP_SUB: return a - b;
        case OP_MUL: return a * b;
        case OP_DIV: return b != 0 ? a / b : 0;
        case OP_MOD: return b != 0 ? a % b : 0;
        case OP_AND: return a & b;
        case OP_OR:  return a | b;
        case OP_XOR: return a ^ b;
        case OP_LSH: return a << (b & 31);
        case OP_RSH: return a >> (b & 31);
        case OP_EQ:  return a == b ? 1 : 0;
        case OP_NE:  return a != b ? 1 : 0;
        case OP_LT:  return a < b ? 1 : 0;
        case OP_LE:  return a <= b ? 1 : 0;
        case OP_GT:  return a > b ? 1 : 0;
        case OP_GE:  return a >= b ? 1 : 0;
        default:     return 0;
    }
}

// =============================================================================
// Interaction Processing Kernel
// =============================================================================

// Redex structure: pair of interacting terms
struct Redex {
    Val loc;      // Location in heap
    Term term;    // The term at that location
};

// Result of an interaction
struct InteractionResult {
    Term result;      // Result term
    uint32_t allocs;  // Number of allocations needed
    bool modified;    // Whether interaction occurred
};

// =============================================================================
// GPU Batch Arithmetic Kernel
// Processes P02 (binary op) + NUM interactions in parallel
// =============================================================================

kernel void batch_arithmetic(
    device const uint32_t* a [[buffer(0)]],
    device const uint32_t* b [[buffer(1)]],
    device uint32_t* results [[buffer(2)]],
    constant uint32_t& op [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    results[id] = compute_op(op, a[id], b[id]);
}

// =============================================================================
// GPU Beta Reduction Kernel
// Processes APP + LAM interactions in parallel
// Each thread handles one potential beta reduction
// =============================================================================

kernel void batch_beta_reduce(
    device Term* heap [[buffer(0)]],
    device const Val* app_locs [[buffer(1)]],    // Locations of APP terms
    device atomic_uint* alloc_ptr [[buffer(2)]], // Atomic allocator
    device atomic_uint* interaction_count [[buffer(3)]],
    constant uint32_t& num_redexes [[buffer(4)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= num_redexes) return;

    Val app_loc = app_locs[id];
    Term func = heap[app_loc];

    // Follow substitution chain
    while (term_is_sub(func)) {
        func = heap[term_val(func)];
    }

    // Check if function is LAM
    if (term_tag(func) != LAM) return;

    Val lam_loc = term_val(func);
    Term arg = heap[app_loc + 1];
    Term body = heap[lam_loc];

    // Perform substitution: body[var := arg]
    // Mark the lambda's variable binding location with substitution
    heap[lam_loc] = term_set_sub(arg);

    // The APP location now holds the body
    heap[app_loc] = body;

    atomic_fetch_add_explicit(interaction_count, 1, memory_order_relaxed);
}

// =============================================================================
// GPU Duplication Kernel
// Processes CO0/CO1 + SUP (annihilation) interactions in parallel
// =============================================================================

kernel void batch_dup_sup_annihilate(
    device Term* heap [[buffer(0)]],
    device const Val* dup_locs [[buffer(1)]],    // Locations of CO0/CO1 terms
    device const Tag* dup_tags [[buffer(2)]],    // CO0 or CO1
    device atomic_uint* interaction_count [[buffer(3)]],
    constant uint32_t& num_redexes [[buffer(4)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= num_redexes) return;

    Val dup_loc = dup_locs[id];
    Tag dup_tag = dup_tags[id];
    Term val = heap[dup_loc];

    // Follow substitution chain
    while (term_is_sub(val)) {
        val = heap[term_val(val)];
    }

    // Check if value is SUP
    if (term_tag(val) != SUP) return;

    Val sup_loc = term_val(val);
    Ext sup_lab = term_ext(val);
    Ext dup_lab = term_ext(heap[dup_loc]); // Get label from original

    // Annihilation only if labels match
    if (dup_lab != sup_lab) return;

    // CO0 gets left, CO1 gets right
    Term result = (dup_tag == CO0) ? heap[sup_loc] : heap[sup_loc + 1];

    // Mark as substituted
    heap[dup_loc] = term_set_sub(result);

    atomic_fetch_add_explicit(interaction_count, 1, memory_order_relaxed);
}

// =============================================================================
// GPU Number Duplication Kernel
// Processes CO0/CO1 + NUM interactions in parallel (trivial case)
// =============================================================================

kernel void batch_dup_num(
    device Term* heap [[buffer(0)]],
    device const Val* dup_locs [[buffer(1)]],
    device atomic_uint* interaction_count [[buffer(2)]],
    constant uint32_t& num_redexes [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= num_redexes) return;

    Val dup_loc = dup_locs[id];
    Term val = heap[dup_loc];

    // Follow substitution chain
    while (term_is_sub(val)) {
        val = heap[term_val(val)];
    }

    // Check if value is NUM
    if (term_tag(val) != NUM) return;

    // Both CO0 and CO1 get the same number
    heap[dup_loc] = term_set_sub(val);

    atomic_fetch_add_explicit(interaction_count, 1, memory_order_relaxed);
}

// =============================================================================
// GPU Erasure Interaction Kernel
// Processes APP + ERA and CO0/CO1 + ERA
// =============================================================================

kernel void batch_erasure(
    device Term* heap [[buffer(0)]],
    device const Val* locs [[buffer(1)]],
    device const Tag* tags [[buffer(2)]],  // What kind of term (APP, CO0, CO1)
    device atomic_uint* interaction_count [[buffer(3)]],
    constant uint32_t& num_redexes [[buffer(4)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= num_redexes) return;

    Val loc = locs[id];
    Tag tag = tags[id];
    Term val;

    if (tag == APP) {
        val = heap[loc];  // Function position
    } else {
        val = heap[loc];  // Duplication target
    }

    // Follow substitution chain
    while (term_is_sub(val)) {
        val = heap[term_val(val)];
    }

    // Check if value is ERA
    if (term_tag(val) != ERA) return;

    // Result is erasure
    heap[loc] = term_set_sub(term_new(ERA, 0, 0));

    atomic_fetch_add_explicit(interaction_count, 1, memory_order_relaxed);
}

// =============================================================================
// GPU Parallel Reduce Kernel
// Each thread tries to reduce one term to weak normal form
// =============================================================================

kernel void parallel_reduce_step(
    device Term* heap [[buffer(0)]],
    device Term* terms [[buffer(1)]],        // Terms to reduce
    device Term* results [[buffer(2)]],       // Results
    device atomic_uint* alloc_ptr [[buffer(3)]],
    device atomic_uint* interaction_count [[buffer(4)]],
    constant uint32_t& num_terms [[buffer(5)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= num_terms) return;

    Term term = terms[id];
    uint32_t local_interactions = 0;

    // Simple reduction loop (limited iterations to prevent infinite loops)
    for (int iter = 0; iter < 100; iter++) {
        // Follow substitution chain
        while (term_is_sub(term)) {
            term = heap[term_val(term)];
        }

        Tag tag = term_tag(term);

        // Check if already a value
        if (tag == NUM || tag == ERA || tag == LAM || tag == SUP) {
            break;
        }

        // Handle APP
        if (tag == APP) {
            Val app_loc = term_val(term);
            Term func = heap[app_loc];

            while (term_is_sub(func)) {
                func = heap[term_val(func)];
            }

            Tag func_tag = term_tag(func);

            if (func_tag == LAM) {
                // Beta reduction
                Val lam_loc = term_val(func);
                Term arg = heap[app_loc + 1];
                Term body = heap[lam_loc];

                heap[lam_loc] = term_set_sub(arg);
                term = body;
                local_interactions++;
            } else if (func_tag == ERA) {
                // Erasure
                term = term_new(ERA, 0, 0);
                local_interactions++;
            } else {
                // Can't reduce further
                break;
            }
        }
        // Handle CO0/CO1
        else if (tag == CO0 || tag == CO1) {
            Val dup_loc = term_val(term);
            Term val = heap[dup_loc];

            while (term_is_sub(val)) {
                val = heap[term_val(val)];
            }

            Tag val_tag = term_tag(val);

            if (val_tag == SUP) {
                Val sup_loc = term_val(val);
                Ext sup_lab = term_ext(val);
                Ext dup_lab = term_ext(term);

                if (dup_lab == sup_lab) {
                    // Annihilation
                    term = (tag == CO0) ? heap[sup_loc] : heap[sup_loc + 1];
                    heap[dup_loc] = term_set_sub(term);
                    local_interactions++;
                } else {
                    // Commutation - complex, skip for now
                    break;
                }
            } else if (val_tag == NUM) {
                // Trivial duplication
                heap[dup_loc] = term_set_sub(val);
                term = val;
                local_interactions++;
            } else if (val_tag == ERA) {
                // Erasure
                heap[dup_loc] = term_set_sub(term_new(ERA, 0, 0));
                term = term_new(ERA, 0, 0);
                local_interactions++;
            } else {
                break;
            }
        }
        // Handle P02 (binary operators)
        else if (tag == P02) {
            Val op_loc = term_val(term);
            Ext op = term_ext(term);
            Term a = heap[op_loc];
            Term b = heap[op_loc + 1];

            while (term_is_sub(a)) a = heap[term_val(a)];
            while (term_is_sub(b)) b = heap[term_val(b)];

            if (term_tag(a) == NUM && term_tag(b) == NUM) {
                uint32_t result = compute_op(op, term_val(a), term_val(b));
                term = term_new(NUM, 0, result);
                local_interactions++;
            } else {
                break;
            }
        }
        else {
            break;
        }
    }

    results[id] = term;
    atomic_fetch_add_explicit(interaction_count, local_interactions, memory_order_relaxed);
}

// =============================================================================
// High-throughput SIMD-style arithmetic kernel
// Processes 4 operations per thread using SIMD
// =============================================================================

kernel void simd_batch_add(
    device const uint4* a [[buffer(0)]],
    device const uint4* b [[buffer(1)]],
    device uint4* results [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    results[id] = a[id] + b[id];
}

kernel void simd_batch_mul(
    device const uint4* a [[buffer(0)]],
    device const uint4* b [[buffer(1)]],
    device uint4* results [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    results[id] = a[id] * b[id];
}

// =============================================================================
// Heap scanning kernel - find all redexes
// =============================================================================

kernel void scan_for_redexes(
    device const Term* heap [[buffer(0)]],
    device atomic_uint* app_count [[buffer(1)]],
    device atomic_uint* dup_count [[buffer(2)]],
    device Val* app_locs [[buffer(3)]],
    device Val* dup_locs [[buffer(4)]],
    constant uint32_t& heap_size [[buffer(5)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= heap_size) return;

    Term term = heap[id];
    if (term_is_sub(term)) return;

    Tag tag = term_tag(term);

    if (tag == APP) {
        uint idx = atomic_fetch_add_explicit(app_count, 1, memory_order_relaxed);
        if (idx < 1000000) {  // Buffer limit
            app_locs[idx] = id;
        }
    } else if (tag == CO0 || tag == CO1) {
        uint idx = atomic_fetch_add_explicit(dup_count, 1, memory_order_relaxed);
        if (idx < 1000000) {
            dup_locs[idx] = id;
        }
    }
}
