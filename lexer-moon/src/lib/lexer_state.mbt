// The Lexer struct encapsulates the state of the parser.
///|
pub struct Lexer {
  // Source code and position
  source : Array[UInt16]
  source_len : Int
  mut pos : Int // Current character index, corresponds to C's `pos` pointer
  end_idx : Int // Exclusive end index (source_len)

  // Parser state
  mut facade : Bool
  mut has_module_syntax : Bool
  last_slash_was_division : Bool
  next_brace_is_class : Bool

  // Tokenizer state
  open_token_stack : Array[OpenToken] // Corresponds to openTokenStack_
  // openTokenDepth is open_token_stack.length()

  dynamic_import_stack : Array[Int] // Stores indices into `imports` Array
  // dynamicImportStackDepth is dynamic_import_stack.length()

  mut last_token_pos : Int // Index of the last significant token, no_token_pos if none

  // Error state
  mut has_error : Bool
  // parse_error in C stored offset. We can store offset or a richer error type.
  // For now, just a position. The public API will form a ParseError struct.
  mut error_pos : Int

  // Results
  // These are mutable and built up during parsing
  pub imports : Array[Import]
  pub exports : Array[Export]

  // Helper indices for managing imports list, similar to C's import_write_head etc.
  // These will store the index of the import in the `imports` Array.
  current_import_idx : Int? // Index of the import being processed (e.g. dynamic import)
  last_committed_import_idx : Int? // Index of the previously fully processed import
}

///|
pub fn new_lexer(source_code : Array[UInt16], length : Int) -> Lexer {
  {
    source: source_code,
    source_len: length,
    pos: -1, // Initialized to -1, first increment makes it 0
    end_idx: length - 1,
    facade: true,
    has_module_syntax: false,
    last_slash_was_division: false,
    next_brace_is_class: false,
    open_token_stack: Array::new(capacity=1024),
    dynamic_import_stack: Array::new(capacity=512),
    last_token_pos: no_token_pos,
    has_error: false,
    error_pos: 0,
    imports: Array::new(),
    exports: Array::new(),
    current_import_idx: None,
    last_committed_import_idx: None,
  }
}

///| Methods for Lexer


///| while (lexer.read_next()) { ... }
pub fn read_next(self: Lexer) -> Bool {
  if self.pos < self.end_idx {
    self.pos += 1
    true
  } else {
    false
  }
}
///| Error handling
pub fn syntax_error(self : Lexer) -> Unit {
  if not(self.has_error) { // Report first error only
    self.has_error = true
    self.error_pos = self.pos // Current position where error was detected
    // In C, pos = end + 1 to stop parsing. We can use a flag or return early.
  }
}

///| To simulate C's `pos = end + 1` to stop parsing.
/// Call this after syntax_error() if immediate stop is needed.
pub fn bail_parsing(self : Lexer) -> Unit {
  self.pos = self.end_idx + 10 // Ensure pos >= end_idx to stop loops
}

///| Helper to get character at current pos, or a default if out of bounds
pub fn current_char_or_default(self : Lexer, default_char : UInt16) -> UInt16 {
  if self.pos >= 0 && self.pos < self.source_len {
    self.source[self.pos]
  } else {
    default_char
  }
}

///| Helper to get character at a specific index
pub fn CHAR_AT_OR_DEFAULT(
  self : Lexer,
  index : Int,
  default_char : UInt16
) -> UInt16 {
  if index >= 0 && index < self.source_len {
    self.source[index]
  } else {
    default_char
  }
}

///| Helper to get character pointed by lastTokenPos
pub fn get_last_token_char(self : Lexer) -> UInt16 {
  if self.last_token_pos == no_token_pos {
    empty_char_code // Simulate C's *EMPTY_CHAR
  } else {
    self.source[self.last_token_pos]
  }
}

///| Helper for open_token_stack depth
pub fn open_token_depth(self : Lexer) -> Int {
  self.open_token_stack.length()
}

///| Helper for dynamic_import_stack depth
pub fn dynamic_import_depth(self : Lexer) -> Int {
  self.dynamic_import_stack.length()
}
