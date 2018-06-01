const warn = @import("std").debug.warn;
const assert = @import("std").debug.assert;
const std = @import("std");
const ArrayList = std.ArrayList;
const debug = std.debug;

const FloxError = error {
    OutOfRange,
    //OutOfMemory,
    //FileNotFound,
};

const OpCode = enum(u8) {
    OP_RETURN,
};

const Chunk = struct {
    //count: u32,
    //capacity: u32,
    //code: &u8,
    code : ArrayList( OpCode),

    pub fn initChunk() Chunk {
        return Chunk {
            .code = ArrayList(OpCode).init(debug.global_allocator)
        };
    }

    pub fn freeChunk( l:& Chunk) void {
        l.code.deinit();
    }

    pub fn writeChunk( l:&Chunk, opCode: OpCode) !void {
        return l.code.append( opCode);
    }
    
    fn simpleInstruction( name: [] const u8, offset: usize) usize {
        warn("{}\n", name);
        return offset+1;
    }

    pub fn disassembleInstruction( self:&Chunk, offset:usize) !usize {
        warn("{} ", offset);

        if( offset >= self.code.len ) {
            return error.OutOfRange;    
        }

        const instruction = self.code.items[offset];
        switch(instruction) {
            OpCode.OP_RETURN => return simpleInstruction( "OP_RETURN", offset),
            else => {
                warn("Unknown opcode {}\n", instruction);
                return error.UnknownOpcode;
                }
                //return offset++; // <-- TBD: Different from book.

        }

        return offset+1;
    }

    pub fn disassembleChunk( self:&Chunk, name:[] const u8) !void {
        warn("== {} ==\n", name);

        var i:usize = 0;
        while(i<self.code.len)
        {
            i = try disassembleInstruction( self, i);
        }
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
    try ccc.writeChunk( OpCode.OP_RETURN);
    assert(ccc.code.len == 1);
    try ccc.disassembleChunk("test chunk");
    warn("Hello, world!\n");
}