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


// Value Array support
const Value = f64;

const ValueArray = ArrayList(Value);

pub fn initValueArray() ValueArray {
    return ArrayList( Value).init(debug.global_allocator);
}

pub fn writeValueArray( va:&ValueArray, v:Value ) !void {
    try va.append(v);
    return;
}

pub fn freeValueArray( va:&ValueArray ) void {
    va.deinit();
}

const INSTRUCTION = union {
    OpCode: OP,
    ValueOffset: usize,
};

// Code Array support
const OP = enum(u8) {
    CONSTANT,
    RETURN,
};

const CodeArray = ArrayList(&const INSTRUCTION);

pub fn initCodeArray() CodeArray {
    return ArrayList(&const INSTRUCTION).init(debug.global_allocator);
}

pub fn writeCodeArray( ca:&CodeArray, opCode:&const INSTRUCTION) !void {
    try ca.append(opCode);
    return;
}

pub fn freeCodeArray( ca:&CodeArray ) void {
    ca.deinit();
}

// Chunk support

const Chunk = struct {
    pub code: ArrayList(& const INSTRUCTION),
    pub constants: ValueArray
};

fn initChunk() Chunk {
    return Chunk {
        .code = initCodeArray(),
        .constants = initValueArray()
    };
}
 
pub fn freeChunk( chunk:& Chunk) void {
    freeCodeArray( &chunk.code);
    freeValueArray( &chunk.constants);
}

pub fn writeChunk( chunk:&Chunk, inst: &const INSTRUCTION ) !void {
    try writeCodeArray( &chunk.code, inst);
    return;
}


// return index into array
pub fn addConstant( chunk:&Chunk, value:Value ) !usize {
    try writeValueArray( &chunk.constants, value);
    return chunk.constants.len -1;
}

fn simpleInstruction( name: [] const u8, offset: usize) usize {
    warn("{}\n", name);
    return offset+1;
}

fn printValue( value: Value) void {
    warn("{}", value);
    return;
}

fn constantInstruction( name: [] const u8, chunk: &Chunk, offset: usize) usize {
    const valueOffset = (chunk.code.items[offset+1]).ValueOffset;
    warn("{} {} '", name, valueOffset);
    printValue( chunk.constants.items[valueOffset]);
    warn( "'\n");
    return offset+2;
}

pub fn disassembleInstruction( chunk:&Chunk, offset:usize) !usize {
    warn("{} ", offset);

    if( offset >=chunk.code.len ) {
        return error.OutOfRange;    
    }

    const instruction = chunk.code.items[offset];
    switch(instruction.OpCode) {
        OP.RETURN => return simpleInstruction( "OP_RETURN", offset),
        OP.CONSTANT => return constantInstruction( "OP_CONSTANT", chunk, offset),
        else => {
            warn("Unknown opcode\n"); // {}\n", instruction);
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

// const x:u8 = 10;
// const all_zero = []u16{0} ** x;
// comptime {
//     assert(all_zero.len == 10);
//     assert(all_zero[5] == 0);
// }




pub fn main() !void {
    var ccc = initChunk();
    defer freeChunk(&ccc);

    // {
    //    .code = ArrayList([] const u8).init(debug.global_allocator)
    //};
    assert(ccc.code.len == 0);
    try writeChunk( &ccc, &(INSTRUCTION { .OpCode = OP.RETURN}));
    assert(ccc.code.len == 1);
    const valueOffset = try addConstant(&ccc, 1.2);
    try writeChunk( &ccc, &(INSTRUCTION { .OpCode = OP.CONSTANT}) );
    try writeChunk( &ccc, &(INSTRUCTION { .ValueOffset = valueOffset}));
    try disassembleChunk( &ccc, "test chunk");
    warn("Hello, world!\n");
}