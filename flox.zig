const warn = @import("std").debug.warn;
const assert = @import("std").debug.assert;
const std = @import("std");
const ArrayList = std.ArrayList;
const debug = std.debug;

const OpCode = enum(u8) {
    OP_RETURN,
};

const Chunk = struct {
    //count: u32,
    //capacity: u32,
    //code: &u8,
    code : ArrayList( u8),

    pub fn initChunk() Chunk {
        return Chunk {
            .code = ArrayList(u8).init(debug.global_allocator)
        };
    }

    pub fn freeChunk( l:& Chunk) void {
        l.code.deinit();
    }

    pub fn writeChunk( l:&Chunk, b: u8) !void {
        return l.code.append( b);
    }
    
    
    
};

const x:u8 = 10;
const all_zero = []u16{0} ** x;
comptime {
    assert(all_zero.len == 10);
    assert(all_zero[5] == 0);
}




pub fn main() !void {
    var ccc = Chunk.initChunk();
    defer ccc.freeChunk();

    // {
    //    .code = ArrayList([] const u8).init(debug.global_allocator)
    //};
    assert(ccc.code.len == 0);
    const item: u8 = 0x1;
    try ccc.writeChunk( item);
    assert(ccc.code.len == 1);
    warn("Hello, world!\n");
}