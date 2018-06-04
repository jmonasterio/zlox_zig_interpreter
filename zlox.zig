// Clox Interpreter ported from CraftingInterpreters.com to ZigLang

// Pros and cons of ZIG.

// Pros
// Compile/link seems really quick.
// Idea of printf("%A dog), being split into seperate code at runtime is cool.
// Comptime stuff is cool: See BINARY_OP instead of original macro in c.
// Error returns are cool.
// C-like.

// Cons
// No easy echo.
// Can't print strings reliably.
// Const propogation
// Error return propogation
// Too much keyword overloading (like const)
// No multiline comments.
// Can't debug inline
// Can't infer type of return value for function.
// I Haven't figured out anything but the debug.global_allocator
// UTF-8/Strings support very limited.
// No pointer math.
// STD library is a shambles.
// For loop over indexes not clear. How do I do: (for int=1; i<10; i++) {}?
// Commas vs Semicolons. Often confused about what needs a semicolon..
// I started out using "classes" (structs with functions), but soon abandoned. Not sure why.
// No printf formatting (like %4.4d)
// Enums (and small structs) can't be passed by value.


const std = @import("std");
const warn = std.debug.warn;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;
const debug = std.debug;
const io = std.io;
const fmt = std.fmt;

const DEBUG_TRACE_EXECUTION = true;
const STACK_MAX = 256;

const ALLOCATOR = debug.global_allocator;

const ZloxError = error {
    OutOfRange,
    OutOfMemory,
    NotImplemented,
    //FileNotFound,
};

inline fn printValue( value: var) !void {
   var buf: [100]u8 = undefined;
   var result = ([] const u8) (try fmt.bufPrint(buf[0..], "{}", value));
   //warn(result);
   return;
}

inline fn printFormattedValue( format: []u8, value: var) !void {
   var buf: [100]u8 = undefined;
   const result = try bufPrint(buf[0..], format, value);
   warn(result);
   return;
}


const Char = u8;
const String = [] Char;
const EOF:Char = 0;

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
        .lines = ArrayList(LineNumber).init(ALLOCATOR) // TBD: SHould wrap like above.
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
    warn("{} {}", name, offset);
    warn("\n");
    return offset+1;
}

fn constantInstruction( name: [] const u8, chunk: &Chunk, offset: Offset) !Offset {
    const valueOffset = (Offset) (chunk.code.items[offset+1]);
    warn("{} {} '", name, valueOffset);
    try printValue( chunk.constants.items[valueOffset]);
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

fn showStack( stackSlice: [] const Value ) !void {
    warn("        ");
    for (stackSlice) |slot| {
        warn("[ ");
        try printValue(slot);
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
inline fn BINARY_OP( comptime op: OP) !void {
    const b = pop();
    const a = pop();

    // This switch happens at compile time. Only one case in resulting generated code.
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
            try showStack( vm.stack[0..vm.stackTop]);    

            _ = try disassembleInstruction( vm.chunk, vm.ip);
        }

        const instruction = readByte();
        switch( instruction )
        {
           OP.RETURN => {
               try printValue( pop() );
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
    len: usize,
    current: Offset,
    line: LineNumber,
};

fn initScanner( source:String) Scanner {
    return Scanner{
        .source = source,
        .start = 0,
        .len = 0,
        .current = 0,
        .line = 1,
    };
}

const TOKEN = enum {
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
    tokenType: TOKEN,
    start: &[]u8, // TBD: Slice from original source.
    //length: usize;
    line: LineNumber,
};

fn makeToken( tokenType: TOKEN, scanner:&Scanner) Token {
    var lexemeSlice = scanner.source[scanner.start..scanner.current];
    return Token{
        .tokenType = tokenType,
        .start = &lexemeSlice,
        .line = scanner.line,

    };
}

fn eofToken( line:LineNumber) Token {
    var eof = "EOF";
    return Token{
        .tokenType = TOKEN.EOF,
        .start = &eof[0..],
        .line = line,

    };
}

fn errorToken( message: String, line:LineNumber) Token {
    return Token{
        .tokenType = TOKEN.ERROR,
        .start = &message[0..],
        .line = line,

    };
}

inline fn isAtEnd(scanner: &Scanner) bool {
    return scanner.current > scanner.source.len;
}

inline fn isLastOrEnd(scanner: &Scanner) bool {
    return scanner.current >= scanner.source.len;
}

inline fn isSecondLastOrEnd(scanner: &Scanner) bool {
    return scanner.current >= scanner.source.len-1;
}


fn advance( scanner:&Scanner) Char {
    scanner.current +=1;
    if( isAtEnd( scanner) ) { 
        return EOF;
    }
    return scanner.source[scanner.current-1];
}

inline fn peek( scanner: &Scanner) Char {
    if( isLastOrEnd( scanner)) { // Book did not have this, because counts on having 0-terminated string.
        return EOF; 
    } else {
        return scanner.source[scanner.current];
    }
}

inline fn peekNext( scanner: &Scanner) Char {
    if( isSecondLastOrEnd( scanner)) { // Book did not have this, because counts on having 0-terminated string.
        return EOF; 
    } else {
        return scanner.source[scanner.current+1];
    }
}

fn match( scanner:&Scanner, char: Char) bool {
    if( peek(scanner) != char) return false; // Like a peek.
    scanner.current+=1;
    return true;
}

inline fn skipComment( scanner: &Scanner) void {
    while(true) {
        const ch:Char = peek( scanner);
        switch( ch) {
            '\n', EOF => break,
            else => advanceIgnore( scanner),
        }
    }
}

fn skipWhitespace( scanner: &Scanner) void {

    while( true) {
        const c:Char = peek( scanner);
        switch( c) {
            ' ', '\r', '\t' => advanceIgnore( scanner),
            '\n' => {scanner.line +=1; _ = advanceIgnore(scanner);},
            '/' => {if( peekNext(scanner)=='/') {skipComment(scanner );} return;},
            else => return
        }
    }
}

fn string( scanner:&Scanner) Token {
    while( peek( scanner) != '"' ) {
        if( peek(scanner) == '\n') {
            scanner.line+=1;
        }
        advanceIgnore(scanner); // TBD: _ = advance() kinda sucks. Return value always ignored but one place.
    }
    if( isAtEnd(scanner)) {
        var msg = "Unterminated string";
        return errorToken( msg[0..], scanner.line);
    }
    advanceIgnore( scanner);
    return makeToken( TOKEN.STRING, scanner);
}

inline fn advanceIgnore( scanner: &Scanner) void {
    _ = advance( scanner);
    return;
} 

fn isDigit( c:Char) bool {
    return c >= '0' and c <= '9';
}

fn number( scanner:&Scanner) Token {
    while( isDigit( peek(scanner))) { 
        advanceIgnore( scanner);
    }
    if( peek(scanner) == '.' and isDigit(peekNext(scanner))) {
        advanceIgnore(scanner);
        while( isDigit( peek(scanner))) {
            advanceIgnore(scanner);
        }
    }
    return makeToken( TOKEN.NUMBER, scanner);

}

fn scanToken( scanner: &Scanner) Token {

    skipWhitespace( scanner);

    scanner.start = scanner.current;

    const c = advance( scanner);
    if( c== EOF) {
        return eofToken(scanner.line);
    }
    _ = switch(c) {
        '(' => return makeToken(TOKEN.LEFT_PAREN,scanner),
        ')' => return makeToken(TOKEN.RIGHT_PAREN,scanner),
        '{' => return makeToken(TOKEN.LEFT_BRACE,scanner),
        '}' => return makeToken(TOKEN.RIGHT_BRACE,scanner),
        ';' => return makeToken(TOKEN.SEMICOLON,scanner),
        ',' => return makeToken(TOKEN.COMMA,scanner),
        '.' => return makeToken(TOKEN.DOT,scanner),
        '-' => return makeToken(TOKEN.MINUS,scanner),
        '+' => return makeToken(TOKEN.PLUS,scanner),
        '/' => return makeToken(TOKEN.SLASH,scanner),
        '*' => return makeToken(TOKEN.STAR,scanner),
        '!' => return makeToken(if( match(scanner,'=')) TOKEN.BANG_EQUAL else TOKEN.BANG,scanner),
        '=' => return makeToken(if( match(scanner,'=')) TOKEN.EQUAL_EQUAL else TOKEN.EQUAL,scanner),
        '<' => return makeToken(if( match(scanner,'=')) TOKEN.LESS_EQUAL else TOKEN.LESS,scanner),
        '>' => return makeToken(if( match(scanner,'=')) TOKEN.GREATER_EQUAL else TOKEN.GREATER,scanner),
        '"' => return string(scanner),
        '0'...'9' => return number(scanner),
        else => {
            var msg = "Unexpected character.";
            return errorToken( msg[0..], scanner.line);
            }
    };


    
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
        warn( "{}", @tagName(token.tokenType));
        warn(" {} \n", (token.start)); // TBD: How do I print a slice?

        if( token.tokenType == TOKEN.EOF) break;

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

        interpretSource(line[0..len]);
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

}

fn deadCode() void {
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

