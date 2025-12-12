// =============================================================================
// HVM4 Metal GPU Acceleration - Pure Zig Implementation
// Uses Zig's Objective-C runtime support to call Metal directly
// =============================================================================

const std = @import("std");
const builtin = @import("builtin");

// Only available on macOS/iOS
pub const is_supported = builtin.os.tag == .macos or builtin.os.tag == .ios;

// =============================================================================
// Objective-C Runtime Types and Functions
// =============================================================================

pub const id = ?*anyopaque;
pub const SEL = ?*anyopaque;
pub const Class = ?*anyopaque;

// Objective-C runtime functions
extern "objc" fn sel_registerName(name: [*:0]const u8) SEL;
extern "objc" fn objc_getClass(name: [*:0]const u8) Class;
extern "objc" fn objc_msgSend() void;

// Metal creation function
extern "Metal" fn MTLCreateSystemDefaultDevice() id;

// =============================================================================
// Message sending helpers
// =============================================================================

fn msgSend0(target: id, selector: SEL) id {
    const func: *const fn (id, SEL) callconv(.c) id = @ptrCast(&objc_msgSend);
    return func(target, selector);
}

fn msgSend1(target: id, selector: SEL, arg1: anytype) id {
    const func: *const fn (id, SEL, @TypeOf(arg1)) callconv(.c) id = @ptrCast(&objc_msgSend);
    return func(target, selector, arg1);
}

fn msgSend2(target: id, selector: SEL, arg1: anytype, arg2: anytype) id {
    const func: *const fn (id, SEL, @TypeOf(arg1), @TypeOf(arg2)) callconv(.c) id = @ptrCast(&objc_msgSend);
    return func(target, selector, arg1, arg2);
}

fn msgSend3(target: id, selector: SEL, arg1: anytype, arg2: anytype, arg3: anytype) id {
    const func: *const fn (id, SEL, @TypeOf(arg1), @TypeOf(arg2), @TypeOf(arg3)) callconv(.c) id = @ptrCast(&objc_msgSend);
    return func(target, selector, arg1, arg2, arg3);
}

// =============================================================================
// Metal GPU Context
// =============================================================================

pub const MetalError = error{
    NotSupported,
    DeviceNotAvailable,
    InitFailed,
    ShaderCompileFailed,
    PipelineCreateFailed,
    BufferAllocFailed,
    CommandFailed,
};

pub const MetalGPU = struct {
    device: id = null,
    queue: id = null,
    library: id = null,

    // GPU heap
    heap_buffer: id = null,
    heap_size: usize = 0,

    device_name: [256]u8 = undefined,
    max_threads: u32 = 1024,

    const Self = @This();

    pub fn init() MetalError!Self {
        if (!is_supported) return MetalError.NotSupported;

        var self = Self{};

        // Get Metal device
        self.device = MTLCreateSystemDefaultDevice();
        if (self.device == null) return MetalError.DeviceNotAvailable;

        // Create command queue
        const newCommandQueue = sel_registerName("newCommandQueue");
        self.queue = msgSend0(self.device, newCommandQueue);
        if (self.queue == null) return MetalError.InitFailed;

        // Get device name
        const name_sel = sel_registerName("name");
        const name_obj = msgSend0(self.device, name_sel);
        if (name_obj != null) {
            const utf8_sel = sel_registerName("UTF8String");
            const cstr_ptr = msgSend0(name_obj, utf8_sel);
            if (cstr_ptr != null) {
                const cstr: [*:0]const u8 = @ptrCast(cstr_ptr);
                const len = std.mem.len(cstr);
                const copy_len = @min(len, self.device_name.len - 1);
                @memcpy(self.device_name[0..copy_len], cstr[0..copy_len]);
                self.device_name[copy_len] = 0;
            }
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (!is_supported) return;

        const release = sel_registerName("release");

        if (self.heap_buffer != null) {
            _ = msgSend0(self.heap_buffer, release);
            self.heap_buffer = null;
        }
        if (self.library != null) {
            _ = msgSend0(self.library, release);
        }
        if (self.queue != null) {
            _ = msgSend0(self.queue, release);
        }
        // Don't release device - it's a system singleton
    }

    pub fn getDeviceName(self: *const Self) []const u8 {
        const len = std.mem.indexOfScalar(u8, &self.device_name, 0) orelse self.device_name.len;
        return self.device_name[0..len];
    }

    /// Allocate GPU buffer
    pub fn allocBuffer(self: *Self, size: usize) MetalError!id {
        if (!is_supported) return MetalError.NotSupported;
        if (self.device == null) return MetalError.DeviceNotAvailable;

        // [device newBufferWithLength:options:]
        const selector = sel_registerName("newBufferWithLength:options:");
        const buffer = msgSend2(self.device, selector, size, @as(u64, 0));
        if (buffer == null) return MetalError.BufferAllocFailed;
        return buffer;
    }

    /// Allocate GPU heap
    pub fn allocHeap(self: *Self, term_count: usize) MetalError!void {
        if (!is_supported) return MetalError.NotSupported;

        const byte_size = term_count * @sizeOf(u64);
        self.heap_buffer = try self.allocBuffer(byte_size);
        self.heap_size = term_count;
    }

    /// Free GPU heap
    pub fn freeHeap(self: *Self) void {
        if (self.heap_buffer != null) {
            const release = sel_registerName("release");
            _ = msgSend0(self.heap_buffer, release);
            self.heap_buffer = null;
            self.heap_size = 0;
        }
    }

    /// Get buffer contents pointer
    pub fn getBufferContents(_: *Self, buffer: id) ?*anyopaque {
        if (!is_supported or buffer == null) return null;
        const contents_sel = sel_registerName("contents");
        return msgSend0(buffer, contents_sel);
    }

    /// Upload data to GPU heap
    pub fn uploadHeap(self: *Self, data: []const u64) MetalError!void {
        if (!is_supported) return MetalError.NotSupported;
        if (self.heap_buffer == null) return MetalError.BufferAllocFailed;

        const contents = self.getBufferContents(self.heap_buffer) orelse return MetalError.BufferAllocFailed;
        const dest: [*]u64 = @ptrCast(@alignCast(contents));
        @memcpy(dest[0..data.len], data);
    }

    /// Download data from GPU heap
    pub fn downloadHeap(self: *Self, data: []u64) MetalError!void {
        if (!is_supported) return MetalError.NotSupported;
        if (self.heap_buffer == null) return MetalError.BufferAllocFailed;

        const contents = self.getBufferContents(self.heap_buffer) orelse return MetalError.BufferAllocFailed;
        const src: [*]const u64 = @ptrCast(@alignCast(contents));
        @memcpy(data, src[0..data.len]);
    }

    /// Compile Metal shader from source string
    pub fn compileShader(self: *Self, source: []const u8) MetalError!void {
        if (!is_supported) return MetalError.NotSupported;
        if (self.device == null) return MetalError.DeviceNotAvailable;

        // Create NSString from source
        const NSString = objc_getClass("NSString");
        const stringWithUTF8 = sel_registerName("stringWithUTF8String:");
        const source_str = msgSend1(NSString, stringWithUTF8, source.ptr);
        if (source_str == null) return MetalError.ShaderCompileFailed;

        // [device newLibraryWithSource:options:error:]
        const newLibrary = sel_registerName("newLibraryWithSource:options:error:");
        self.library = msgSend3(self.device, newLibrary, source_str, @as(id, null), @as(id, null));
        if (self.library == null) return MetalError.ShaderCompileFailed;
    }
};

// =============================================================================
// Global GPU Instance
// =============================================================================

var global_gpu: ?MetalGPU = null;

/// Check if Metal is available
pub fn isAvailable() bool {
    if (!is_supported) return false;
    return MTLCreateSystemDefaultDevice() != null;
}

/// Initialize global Metal context
pub fn init() MetalError!void {
    if (global_gpu != null) return;
    global_gpu = try MetalGPU.init();
}

/// Deinitialize global Metal context
pub fn deinit() void {
    if (global_gpu) |*gpu| {
        gpu.deinit();
        global_gpu = null;
    }
}

/// Get global GPU
pub fn getGPU() ?*MetalGPU {
    return if (global_gpu) |*gpu| gpu else null;
}

// =============================================================================
// Benchmark Results
// =============================================================================

pub const BenchResult = struct {
    ops: u64,
    ns: u64,
};

/// Benchmark GPU initialization and basic operations
pub fn benchGPUInit() BenchResult {
    if (!is_supported) return .{ .ops = 0, .ns = 1 };

    var timer = std.time.Timer.start() catch return .{ .ops = 0, .ns = 1 };

    // Test device creation
    const device = MTLCreateSystemDefaultDevice();
    if (device == null) return .{ .ops = 0, .ns = 1 };

    const ns = timer.read();
    return .{ .ops = 1, .ns = ns };
}

// =============================================================================
// CPU SIMD Fallback Operations
// =============================================================================

/// SIMD batch add (CPU with Zig vectors)
pub fn cpuBatchAdd(a: []const u32, b: []const u32, results: []u32) void {
    const Vec8 = @Vector(8, u32);
    const len = @min(a.len, @min(b.len, results.len));

    var i: usize = 0;
    while (i + 8 <= len) : (i += 8) {
        const va: Vec8 = a[i..][0..8].*;
        const vb: Vec8 = b[i..][0..8].*;
        results[i..][0..8].* = va + vb;
    }

    while (i < len) : (i += 1) {
        results[i] = a[i] + b[i];
    }
}

/// SIMD batch multiply (CPU with Zig vectors)
pub fn cpuBatchMul(a: []const u32, b: []const u32, results: []u32) void {
    const Vec8 = @Vector(8, u32);
    const len = @min(a.len, @min(b.len, results.len));

    var i: usize = 0;
    while (i + 8 <= len) : (i += 8) {
        const va: Vec8 = a[i..][0..8].*;
        const vb: Vec8 = b[i..][0..8].*;
        results[i..][0..8].* = va * vb;
    }

    while (i < len) : (i += 1) {
        results[i] = a[i] * b[i];
    }
}

/// Batch add (GPU when available, CPU fallback)
pub fn batchAdd(a: []const u32, b: []const u32, results: []u32) void {
    // TODO: Add GPU path when compute pipelines are fully set up
    cpuBatchAdd(a, b, results);
}

/// Batch multiply (GPU when available, CPU fallback)
pub fn batchMul(a: []const u32, b: []const u32, results: []u32) void {
    cpuBatchMul(a, b, results);
}

// =============================================================================
// Tests
// =============================================================================

test "cpu batch add" {
    var a = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var b = [_]u32{ 10, 20, 30, 40, 50, 60, 70, 80 };
    var results: [8]u32 = undefined;

    cpuBatchAdd(&a, &b, &results);

    for (0..8) |i| {
        try std.testing.expectEqual(a[i] + b[i], results[i]);
    }
}

test "cpu batch mul" {
    var a = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var b = [_]u32{ 10, 20, 30, 40, 50, 60, 70, 80 };
    var results: [8]u32 = undefined;

    cpuBatchMul(&a, &b, &results);

    for (0..8) |i| {
        try std.testing.expectEqual(a[i] * b[i], results[i]);
    }
}
