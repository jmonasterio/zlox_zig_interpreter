const warn = @import("std").debug.warn;
const assert = @import("std").debug.assert;
const std = @import("std");
const ArrayList = std.ArrayList;
const debug = std.debug;
const io = std.io;

const DEBUG_TRACE_EXECUTION = true;
const STACK_MAX = 256;

const ALLOCATOR = debug.global_allocator;

const ZloxError = error {
    OutOfRange,
    OutOfMemory,
    NotImplemented,
    //FileNotFound,
};


const String = [] u8;

const Offset = usize;

// Value Array support
const Value = f64;
const LineNumber = u32;

const ValueArray = ArrayList(Value);

pub fn initValueArray() ValueArray {
    return ArrayList( Value).init(ALLOCATOR);
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
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    RETURN,
};

const CodeArray = ArrayList(INSTRUCTION);

pub fn initCodeArray() CodeArray {
    return ArrayList(INSTRUCTION).init(ALLOCATOR);
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
        .lines = ArrayList(LineNumber).init(ALLOCATOR)
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
        OP.ADD => return simpleInstruction( "OP_ADD", offset),
        OP.SUBTRACT => return simpleInstruction( "OP_SUBTRACT", offset),
        OP.DIVIDE => return simpleInstruction( "OP_DIVIDE", offset),
        OP.MULTIPLY => return simpleInstruction( "OP_MULTIPLY", offset),
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

fn add( a:Value, b:Value) Value {
    return a+b;
}

// Zig macro is partially executed at runtime. Will assert if you pass an illegal OP as constnat
fn BINARY_OP( comptime op: OP) !void {
    const b = pop();
    const a = pop();

    const result = switch( op){
        OP.ADD => a+b,
        OP.SUBTRACT => a-b,
        OP.MULTIPLY => b*a,
        OP.DIVIDE => a/b,
        else => { comptime assert( false); }, //"Not supported"),
    };

    try push( result );
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
           OP.ADD => { try BINARY_OP(OP.ADD); },
           OP.SUBTRACT => { try BINARY_OP(OP.SUBTRACT); },
           OP.MULTIPLY => { try BINARY_OP(OP.MULTIPLY); },
           OP.DIVIDE => { try BINARY_OP(OP.DIVIDE); },
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

const Scanner = struct {
    source: String,
    start: Offset,
    current: Offset,
    line: LineNumber,
};

fn initScanner( source:String) Scanner {
    return Scanner{
        .source = source,
        .start = 0,
        .current = 0,
        .line = 1,
    };
}

const TokenType = enum {
    // Single-character tokens.
  LEFT_PAREN, RIGHT_PAREN,
  LEFT_BRACE, RIGHT_BRACE,
  COMMA, DOT, MINUS, PLUS,
  SEMICOLON, SLASH, STAR,

  // One or two character tokens.
  BANG, BANG_EQUAL,
  EQUAL, EQUAL_EQUAL,
  GREATER, GREATER_EQUAL,
  LESS, LESS_EQUAL,

  // Literals.
  IDENTIFIER, STRING, NUMBER,

  // Keywords.
  AND, CLASS, ELSE, FALSE,
  FUN, FOR, IF, NIL, OR,
  PRINT, RETURN, SUPER, THIS,
  TRUE, VAR, WHILE,

  ERROR,
  EOF
};

const Token = struct {
    ttype: TokenType,
    start: &[]u8, // TBD: Slice from original source.
    //length: usize;
    line: LineNumber,
};

fn isAtEnd(scanner: &Scanner) bool {
    return scanner.current == 0;
}

fn makeToken( ttype: TokenType, lexemeSlice: String, line:LineNumber) Token {
    return Token{
        .ttype = ttype,
        .start = &lexemeSlice[0..],
        .line = line,

    };
}

fn errorToken( message: String, line:LineNumber) Token {
    return Token{
        .ttype = TokenType.ERROR,
        .start = &message[0..],
        .line = line,

    };
}

fn scanToken( scanner: &Scanner) Token {

    scanner.start = scanner.current;
    if( isAtEnd( scanner) ) {
        return makeToken( TokenType.EOF, "", scanner.line);
    }
    var msg = "Unexpected character.";
    return errorToken( msg[0..], scanner.line);
}

fn compile( source:String) void {
    var scanner = initScanner( source);

    var line:LineNumber = 0;
    while(true) {
        const token =scanToken(&scanner );
        if( token.line != line) {
            warn( "{} ", token.line);
            line = token.line;
        } else {
            warn( "   | ");
        }
        warn("{} {} \n", (u6) (token.ttype), token.start);

        if( token.ttype == TokenType.EOF) break;

    }

    return;
}

fn interpretSource( source:String) void {
    compile( source);
    return;
}

fn interpret( chunk: &Chunk) !void {
    vm.chunk = chunk;
    vm.ip = 0;
    try run();
    return;
}

const LINE_LEN = 1000;

pub fn readLine(buf: String) !usize {
    var stdin = io.getStdIn() catch return error.StdInUnavailable;
    var adapter = io.FileInStream.init(&stdin);
    var stream = &adapter.stream;
    var index: usize = 0;
    while (true) {
        const byte = stream.readByte() catch return error.EndOfFile;
        switch (byte) {
            '\r' => {
                // trash the following \n
                _ = stream.readByte() catch return error.EndOfFile;
                return index;
            },
            '\n' => return index,
            else => {
                if (index == LINE_LEN) return error.InputTooLong;
                buf[index] = byte;
                index += 1;
            },
        }
    }
}

fn repl() !void {
    while(true) {
        warn( "> ");
        var line = String {0} ** LINE_LEN;
        const len = try readLine( line[0..]);
        warn("\n");

        interpretSource(line[0..]);
    }
}

fn runFile( path: String ) !void {
    const source = try std.io.readFileAlloc(ALLOCATOR, path);
    interpretSource( source);
    return;
}

pub fn main( ) !void {
    initVM();
    defer freeVM();

    const it: &std.os.ArgIteratorWindows = &std.os.ArgIteratorWindows.init();
    var argv = ArrayList(String).init(ALLOCATOR);
    defer argv.deinit();
    while( true) {
        const next = try it.next( ALLOCATOR) ?? break;
        try argv.append(next);
    }

    const argc = argv.len;
    if( argc == 1) {
        try repl();
    } else if( argc == 2) {
        const file = argv.items[1]; // Skip EXE name which is 0th item.
        //defer file.deinit();
        try runFile( file);
    } else
    {
        warn( "Usage zlox [path]\n");
        // TBD: exit();
    }

    var chunk = initChunk();
    defer freeChunk(&chunk);

    // {
    //    .code = ArrayList([] const u8).init(ALLOCATOR)
    //};
    assert(chunk.code.len == 0);
    var valueOffset = try addConstant(&chunk, 1.2);
    
    try writeChunk( &chunk, (INSTRUCTION) (OP.CONSTANT), 123);
    try writeChunk( &chunk, (INSTRUCTION) (valueOffset), 123);
    assert(chunk.code.len == 2);

    valueOffset = try addConstant(&chunk, 3.4);
    try writeChunk(&chunk, (INSTRUCTION) (OP.CONSTANT), 123);
    try writeChunk(&chunk, (INSTRUCTION) (valueOffset), 123);

    try writeChunk(&chunk, (INSTRUCTION) (OP.ADD), 123);

    valueOffset = try addConstant(&chunk, 5.6);
    try writeChunk(&chunk, (INSTRUCTION) (OP.CONSTANT), 123);
    try writeChunk(&chunk, (INSTRUCTION) (valueOffset), 123);

    try writeChunk(&chunk, (INSTRUCTION) (OP.DIVIDE), 123);

    try writeChunk( &chunk, (INSTRUCTION) (OP.NEGATE), 123);
    try writeChunk( &chunk, (INSTRUCTION) (OP.RETURN), 123);
    try disassembleChunk( &chunk, "test chunk");
    warn("== Interpret\n");
    try interpret( &chunk);
}

