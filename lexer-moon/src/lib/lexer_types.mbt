// lexer_types.mbt

// Corresponds to enum ImportType in C
pub enum ImportType {
  Static
  Dynamic
  ImportMeta
  StaticSourcePhase
  DynamicSourcePhase
  StaticDeferPhase
  DynamicDeferPhase
}

// To represent the special `dynamic` pointer values from C
pub enum DynamicSpec {
  StandardImport // C: STANDARD_IMPORT (0x1)
  IsImportMeta // C: IMPORT_META (0x2)
  DynamicOffset(Int) // C: pointer to dynamic import start, now an offset
}

// Corresponds to struct Import in C
// Pointers are replaced by Int offsets relative to the source start.
// Option[Int] is used for pointers that can be NULL or 0.
pub struct Import {
  mut start : Int // offset of the imported module string
  mut end : Option[Int] // offset of the end of the imported module string
  statement_start : Int // offset of the start of the whole import statement
  mut statement_end : Option[Int] // offset of the end of the whole import statement
  mut assert_index : Option[Int] // offset of import assertion, if any
  dynamic_spec : DynamicSpec
  mut safe : Bool // true if string literal for dynamic import is safe
  import_ty : ImportType
  // 'next' pointer is implicit by order in ArrayBuffer[Import]
}

// Corresponds to enum OpenTokenState in C
pub enum OpenTokenState {
  AnyParen // (
  AnyBrace // {
  Template // `
  TemplateBrace // ${
  ImportParen // import(),
  ClassBrace
  AsyncParen // async() - Not explicitly in C enum but good to have if seen
} derive(Eq)

// Corresponds to struct OpenToken in C
pub struct OpenToken {
  token : OpenTokenState
  pos : Int // offset of the token before this open token
}

// Corresponds to struct Export in C
pub struct Export {
  start : Int // offset of exported name
  end : Int // offset of end of exported name
  local_start : Option[Int] // offset of local name (if aliased)
  local_end : Option[Int] // offset of end of local name
  // 'next' pointer is implicit by order in ArrayBuffer[Export]
}

// Structure to hold parsing results, to be returned by the public `parse` function.
pub struct ParseResult {
  imports: Array[Import]
  exports: Array[Export]
  facade: Bool
  has_module_syntax: Bool
}

// Structure for parsing errors
pub struct ParseError {
  message: String
  position: Int // Offset of the error in the source
}