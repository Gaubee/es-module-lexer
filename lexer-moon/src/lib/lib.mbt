///| Parses a JavaScript/TypeScript source represented as an array of UTF-16 code units.
///
/// Args:
///   source_chars: The source code as an array of `UInt16` values.
///   source_length: The length of the `source_chars` array to consider.
///
/// Returns:
///   `Ok(ParseResult)` on successful parsing, containing lists of imports and exports,
///   and other module metadata.
///   `Err(ParseError)` if a syntax error is encountered.
pub fn parse(
  source_chars : Array[UInt16],
  source_length : Int
) -> Result[ParseResult, ParseError] {
  let lexer = new_lexer(source_chars, source_length)
  if lexer.parse_internal() {
    // Successfully parsed
    let result = {
      imports: lexer.imports.copy(),
      exports: lexer.exports.copy(),
      facade: lexer.facade,
      has_module_syntax: lexer.has_module_syntax,
    }
    Ok(result)
  } else {
    // Parsing failed
    Err({ message: "Syntax error", position: lexer.error_pos })
  }
}
