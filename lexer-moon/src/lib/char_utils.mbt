// CHAR_UTILS.mbt

// Note: In C, char16_t is used. We use UInt16 to represent UTF-16 code units.
// ASCII values are used for comparisons.

// Corresponds to isBr
pub fn is_br(c: UInt16) -> Bool {
  c == '\r'.to_int().to_uint16() || c == '\n'.to_int().to_uint16()
}

// Corresponds to isWsNotBr
pub fn is_ws_not_br(c: UInt16) -> Bool {
  c == CHAR_TAB || // 9
  c == CHAR__V || // \v
  c == CHAR__F || // 12
  c == CHAR_SPACE || // 32
  c == CHAR_NON_BREAKING_SPACE // non-breaking space
}

// Corresponds to isBrOrWs
pub fn is_br_or_ws(c: UInt16) -> Bool {
  (c > (8:UInt16) && c < (14:UInt16)) || c == (32:UInt16) || c == (160:UInt16)
}

// Corresponds to isBrOrWsOrPunctuatorNotDot
pub fn is_br_or_ws_or_punctuator_not_dot(c: UInt16) -> Bool {
  is_br_or_ws(c) || (is_punctuator(c) && c != '.'.to_int().to_uint16())
}

// Corresponds to isQuote
pub fn is_quote(ch: UInt16) -> Bool {
  ch == '\''.to_int().to_uint16() || ch == '"'.to_int().to_uint16()
}

// Moved from parsing_helpers.mbt
pub fn is_punctuator(ch: UInt16) -> Bool {
  let c = ch.to_int()
  c == 33 || c == 37 || c == 38 || (c >= 40 && c <= 47) || (c >= 58 && c <= 63) || c == 91 || c == 93 || c == 94 || (c >= 123 && c <= 126)
}

// Moved from parsing_helpers.mbt
pub fn is_expression_punctuator(ch: UInt16) -> Bool {
  // Based on C code for isExpressionPunctuator
  // !%&(*+,-.:;<=>?[^{|~
  match ch {
    // '!', '%', '&'
    (33:UInt16) | (37:UInt16) | (38:UInt16) => true
    // '(', '*', '+', ',', '-', '.', '/'
    (40:UInt16) | (42:UInt16) | (43:UInt16) | (44:UInt16) | (45:UInt16) | (46:UInt16) | (47:UInt16) => true
    // ':', ';', '<', '=', '>', '?', '@'
    (58:UInt16) | (59:UInt16) | (60:UInt16) | (61:UInt16) | (62:UInt16) | (63:UInt16) | (64:UInt16) => true
    // '[', '^'
    (91:UInt16) | (94:UInt16) => true
    // '{', '|', '~'
    (123:UInt16) | (124:UInt16) | (126:UInt16) => true
    _ => false
  }
}
