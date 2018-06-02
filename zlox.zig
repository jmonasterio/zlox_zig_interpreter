const warn = @import("std").debug.warn;
const assert = @import("std").debug.assert;
const std = @import("std");
const ArrayList = std.ArrayList;
const debug = std.debug;

const DEBUG_TRACE_EXECUTION = true;
const STACK_MAX = 256;

const ZloxError = error {
    OutOfRange,
    OutOfMemory,
    //FileNotFound,
};

const Offset = usize;

// Value Array support
const Value = f64;
const LineNumber = u32;

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

// Code array holds either opcodes (enum) or value-offsets (offset into valueArray).
// Tried using union to be more typesafe, but UNIONS can't be passed by value in ZIG.
// That means array now hold addresses, which is awful (huge).
//const INSTRUCTION = union {
//    OpCode: OP,
//    ValueOffset: usize,
//};

const INSTRUCTION = usize;

// Code Array support
const OP = enum(INSTRUCTION) {
    CONSTANT,
    NEGATE,
    RETURN,
};

const CodeArray = ArrayList(INSTRUCTION);

pub fn initCodeArray() CodeArray {
    return ArrayList(INSTRUCTION).init(debug.global_allocator);
}

pub fn writeCodeArray( ca:&CodeArray, opCode:INSTRUCTION) !void {
    try ca.append(opCode);
    return;
}

pub fn freeCodeArray( ca:&CodeArray ) void {
    ca.deinit();
}

// Chunk support

const Chunk = struct {
    pub code: ArrayList(INSTRUCTION),
    pub constants: ValueArray,
    pub lines: ArrayList(LineNumber),
};

fn initChunk() Chunk {
    return Chunk {
        .code = initCodeArray(),
        .constants = initValueArray(),
        .lines = ArrayList(LineNumber).init(debug.global_allocator)
    };
}
 
pub fn freeChunk( chunk:& Chunk) void {
    freeCodeArray( &chunk.code);
    freeValueArray( &chunk.constants);
    chunk.lines.deinit();
}

pub fn writeChunk( chunk:&Chunk, inst: INSTRUCTION, line:LineNumber ) !void {
    try writeCodeArray( &chunk.code, inst);
    try chunk.lines.append(line);
    return;
}


// return index into array
pub fn addConstant( chunk:&Chunk, value:Value ) !Offset {
    try writeValueArray( &chunk.constants, value);
    return chunk.constants.len -1;
}

fn simpleInstruction( name: [] const u8, offset: Offset) Offset {
    warn("{}\n", name);
    return offset+1;
}

fn printValue( value: Value) void {
    warn("{}", value);
    return;
}

fn constantInstruction( name: [] const u8, chunk: &Chunk, offset: Offset) Offset {
    const valueOffset = (Offset) (chunk.code.items[offset+1]);
    warn("{} {} '", name, valueOffset);
    printValue( chunk.constants.items[valueOffset]);
    warn( "'\n");
    return offset+2;
}

pub fn disassembleInstruction( chunk:&Chunk, offset:Offset) !Offset {
    warn("{} ", offset);
    if( offset > 0) {
        warn( "   | ");
    } else {
        warn("{} ", chunk.lines.items[offset]);
    }

    if( offset >=chunk.code.len ) {
        return error.OutOfRange;    
    }

    const opCode: OP = (OP) (chunk.code.items[offset]);
    switch(opCode) {
        OP.RETURN => return simpleInstruction( "OP_RETURN", offset),
        OP.NEGATE => return simpleInstruction( "OP_NEGATE", offset),
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

    var i:Offset = 0;
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


const VM = struct {
    pub chunk: &Chunk,
    pub ip: Offset,
    pub stack: [STACK_MAX] Value, // TBD: Could not get slice to work because of CONST
    pub stackTop: Offset
};

var vm : VM = undefined;

// Book had this function, but don't really need. Just sorta following along.
inline fn resetStack() Offset {
    return 0;
}

fn initVM() void {
    var chunk = initChunk();
    vm = VM { .chunk = &chunk,
              .ip = 0,
              .stack = ([]Value{0} ** STACK_MAX), // slice
              .stackTop = resetStack() };  
}

fn freeVM() void {
}

fn readByte() OP {
    var slice = vm.chunk.code.items[0..];
    const op = (OP) (slice[vm.ip]);
    vm.ip += 1;
    return op;
}

fn readOffset() Offset { 
    
    var slice = vm.chunk.code.items[0..];
    const offset = slice[vm.ip];
    vm.ip+=1;
    return offset;
}

fn readConstant() Value {
    const offset = readOffset();
    return vm.chunk.constants.items[offset];
}

const InterpretResult = error {
    COMPILE_ERROR,
    RUNTIME_ERROR
};

fn showStack( stackSlice: [] const Value ) void {
    warn("        ");
    for (stackSlice) |slot| {
        warn("[ ");
        printValue(slot);
        warn("] ");
    }
    warn("\n");
    return;
}

fn push( value: Value) !void {
    vm.stack[vm.stackTop] = value;
    vm.stackTop +=1;

    if( vm.stackTop > STACK_MAX) {
        return ZloxError.OutOfMemory;
    }
}

fn pop() Value {
    vm.stackTop -=1;

    return vm.stack[vm.stackTop];
}


fn run() !void {
    while(true) {

        if( DEBUG_TRACE_EXECUTION) {
            showStack( vm.stack[0..vm.stackTop]);    

            _ = try disassembleInstruction( vm.chunk, vm.ip);
        }

        const instruction = readByte();
        switch( instruction )
        {
           OP.RETURN => {
               printValue(pop() );
               warn("\n");
               return;
           }, 
           OP.CONSTANT => {
               const constant:Value = readConstant();
               try push( constant);
               warn("\n");
           },
           OP.NEGATE => {
               try push( - pop());
           },
           else => return InterpretResult.RUNTIME_ERROR,
        }
    }
}

fn interpret( chunk: &Chunk) !void {
    vm.chunk = chunk;
    vm.ip = 0;
    try run();
    return;
}


pub fn main() !void {
    initVM();
    defer freeVM();

    var chunk = initChunk();
    defer freeChunk(&chunk);

    // {
    //    .code = ArrayList([] const u8).init(debug.global_allocator)
    //};
    assert(chunk.code.len == 0);
    const valueOffset = try addConstant(&chunk, 1.2);
    
    try writeChunk( &chunk, (INSTRUCTION) (OP.CONSTANT), 123);
    try writeChunk( &chunk, (INSTRUCTION) (valueOffset), 123);
    assert(chunk.code.len == 2);
    try writeChunk( &chunk, (INSTRUCTION) (OP.NEGATE), 123);
    try writeChunk( &chunk, (INSTRUCTION) (OP.RETURN), 123);
    assert(chunk.code.len == 4);
    try disassembleChunk( &chunk, "test chunk");
    warn("== Interpret\n");
    try interpret( &chunk);
}

