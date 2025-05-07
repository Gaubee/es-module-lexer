// Corresponds to C's memcmp for checking keywords
// Checks if source from start_idx matches pattern
pub fn source_matches(lexer: Lexer, start_idx: Int, pattern: Array[UInt16]) -> Bool {
  if start_idx < 0 || start_idx + pattern.length() > lexer.source_len {
    return false
  }
  for i = 0; i < pattern.length(); i += 1 {
    if lexer.source[start_idx + i] != pattern[i] {
      return false
    }
  }
  return true
}

// Check if char at `idx` is start of spread operator `...`
// `idx` points to the LAST dot.
///|
pub fn is_spread(lexer : Lexer, idx : Int) -> Bool {
  if idx >= 2 { // Need at least two preceding characters
    lexer.source[idx] == CHAR_DOT &&
    lexer.source[idx - 1] == CHAR_DOT &&
    lexer.source[idx - 2] == CHAR_DOT
  } else {
    false
  }
}

// Corresponds to isBrOrWsOrPunctuatorOrSpreadNotDot
///|
pub fn is_br_or_ws_or_punctuator_or_spread_not_dot(
  lexer : Lexer,
  CHAR_IDX : Int
) -> Bool {
  if CHAR_IDX < 0 || CHAR_IDX >= lexer.source_len {
    return true
  } // Treat out of bounds as separator
  let c = lexer.source[CHAR_IDX]
  is_br_or_ws(c) ||
  (is_punctuator(c) && (is_spread(lexer, CHAR_IDX) || c != CHAR_DOT))
}

// Corresponds to keywordStart
///|
pub fn keyword_start(lexer : Lexer, at_pos : Int) -> Bool {
  at_pos == 0 || is_br_or_ws_or_punctuator_or_spread_not_dot(lexer, at_pos - 1)
}

// Corresponds to readPrecedingKeyword1
///|
pub fn read_preceding_keyword1(
  lexer : Lexer,
  keyword_end_pos : Int,
  c1 : UInt16
) -> Bool {
  if keyword_end_pos < 0 || keyword_end_pos >= lexer.source_len {
    return false
  }
  lexer.source[keyword_end_pos] == c1 &&
  (
    keyword_end_pos == 0 ||
    is_br_or_ws_or_punctuator_not_dot(lexer.source[keyword_end_pos - 1])
  )
}

// Corresponds to readPrecedingKeywordn
///|
pub fn read_preceding_keywordn(
  lexer : Lexer,
  keyword_end_pos : Int,
  pattern : Array[UInt16]
) -> Bool {
  let n = pattern.length()
  if n == 0 {
    return true
  } // Empty pattern matches
  let keyword_start_pos = keyword_end_pos - n + 1
  if keyword_start_pos < 0 {
    return false
  }
  source_matches(lexer, keyword_start_pos, pattern) &&
  (
    keyword_start_pos == 0 ||
    is_br_or_ws_or_punctuator_or_spread_not_dot(lexer, keyword_start_pos - 1)
  )
}

// Skips whitespace and comments. Updates lexer.pos.
// Returns the first non-whitespace/comment character.
// `br` (bool): if true, newlines are considered whitespace. If false, newlines are terminators.
///|
pub fn comment_whitespace(lexer : Lexer, br_is_whitespace : Bool) -> UInt16 {
  while lexer.pos < lexer.end_idx {
    let ch = lexer.source[lexer.pos]
    if ch == CHAR_SLASH {
      if lexer.pos + 1 < lexer.end_idx {
        let next_ch = lexer.source[lexer.pos + 1]
        if next_ch == CHAR_SLASH {
          line_comment(lexer) // Advances lexer.pos
          // line_comment leaves pos on the char before LF or at end_idx
          // The outer loop's pos increment will move past it or break
          if lexer.pos < lexer.end_idx {
            lexer.pos += 1
            continue
          } else {
            break
          }
        } else if next_ch == CHAR_ASTERISK {
          block_comment(lexer, br_is_whitespace) // Advances lexer.pos
          if lexer.has_error {
            return (0 : UInt16)
          } // block_comment can set error
          if lexer.pos < lexer.end_idx {
            lexer.pos += 1
            continue
          } else {
            break
          }
        } else {
          return ch // Not a comment, just a slash
        }
      } else {
        return ch // EOF after slash
      }
    } else if br_is_whitespace {
      if not(is_br_or_ws(ch)) {
        return ch
      } // !br_is_whitespace, so newline is not whitespace
    } else if not(is_ws_not_br(ch)) {
      return ch
    }
    lexer.pos += 1
  }
  return (0 : UInt16) // EOF
}

pub fn line_comment(lexer: Lexer) -> {
  lexer.pos += 2 // Skip "//"
  while lexer.pos < lexer.end_idx {
    let ch = lexer.source[lexer.pos]
    if ch == CHAR_LF || ch == CHAR_CR {
      // Position will be on the newline char. The outer loop will advance past it.
      // To match C behavior of returning from lineComment(), we set pos to char *before* newline.
      // The caller of commentWhitespace will then advance pos.
      // However, commentWhitespace advances pos itself.
      // C: `lineComment()` -> `pos` is on `\n`. `commentWhitespace` `pos++`.
      // Let's make line_comment consume the newline as well if possible, or position before it.
      // The C loop `while (pos++ < end)` implies `pos` is advanced before next check.
      // My `comment_whitespace` loop also does `lexer.pos += 1`.
      // So `line_comment` should leave `pos` at the newline character.
      return
    }
    lexer.pos += 1
  }
  // Reached EOF
}

///|
pub fn block_comment(lexer : Lexer, br_is_whitespace : Bool) -> Unit {
  lexer.pos += 2 // Skip "/*"
  while lexer.pos < lexer.end_idx {
    let ch = lexer.source[lexer.pos]
    if not(br_is_whitespace && is_br(ch)) {
      // C: `if (!br && isBr(ch)) return;`
      // This means block comment parsing stops if br_is_whitespace is false and newline is found.
      // The current char `ch` (newline) should then be processed by `comment_whitespace`.
      // So, we should NOT advance pos here.
      lexer.pos -= 1 // backtrack so comment_whitespace re-evaluates this char.
      return
    }
    if ch == CHAR_ASTERISK && lexer.pos + 1 < lexer.end_idx {
      if lexer.source[lexer.pos + 1] == CHAR_SLASH {
        lexer.pos += 1 // consume "*/", pos will be on '/'
        return
      }
    }
    lexer.pos += 1
  }
  // Unterminated block comment
  lexer.syntax_error()
}

///|
pub fn string_literal(lexer : Lexer, quote_char : UInt16) -> Unit {
  // lexer.pos is currently on the opening quote.
  // The loop should start checking char after quote.
  while true {
    lexer.pos += 1
    if lexer.pos >= lexer.end_idx {
      lexer.syntax_error() // Unterminated string
      return
    }
    let ch = lexer.source[lexer.pos]
    if ch == quote_char {
      return // lexer.pos is on the closing quote
    }
    if ch == CHAR_BACKSLASH {
      lexer.pos += 1 // Skip char after backslash
      if lexer.pos >= lexer.end_idx {
        lexer.syntax_error()
        return
      }
      // Handle CRLF after backslash
      if lexer.source[lexer.pos] == CHAR_CR &&
        lexer.pos + 1 < lexer.end_idx &&
        lexer.source[lexer.pos + 1] == CHAR_LF {
        lexer.pos += 1 // consume LF
      }
    } else if is_br(ch) {
      // Illegal newline in string literal (C behavior)
      lexer.syntax_error()
      return
    }
  }
}

///|
fn regex_character_class(lexer : Lexer) -> UInt16 {
  // lexer.pos is on '['
  while lexer.read_next() {
    let ch = lexer.source[lexer.pos]
    if ch == CHAR_BRACKET_CLOSE {
      return ch // pos is on ']'
    }
    if ch == CHAR_BACKSLASH {
      lexer.pos += 1 // Skip escaped char
    } else if ch == CHAR_LF || ch == CHAR_CR {
      break // Illegal newline
    }
  }
  lexer.syntax_error()
  0
}

///|
pub fn regular_expression(lexer : Lexer) -> Unit {
  // lexer.pos is on the opening '/'
  while true {
    lexer.pos += 1
    if lexer.pos >= lexer.end_idx {
      lexer.syntax_error()
      return
    }
    let ch = lexer.source[lexer.pos]
    if ch == CHAR_SLASH { // Closing '/'
      // Note: Regex flags might follow, C code doesn't parse them, just finds closing /
      return // pos is on closing '/'
    }
    if ch == CHAR_BRACKET_OPEN { // Character class '['
      let _ = regex_character_class(lexer) // pos will be on ']' or error
      if lexer.has_error {
        return
      }
    } else if ch == CHAR_BACKSLASH {
      lexer.pos += 1 // Skip escaped char
      if lexer.pos >= lexer.end_idx {
        lexer.syntax_error()
        return
      }
    } else if ch == CHAR_LF || ch == CHAR_CR {
      lexer.syntax_error()
      return // Illegal newline
    }
  }
}

///|
pub fn template_string(lexer : Lexer) -> Unit {
  // lexer.pos is on opening '`' or closing '}' of a template expression
  // This function is called when a '`' is encountered, or when '}' is encountered if
  // the matching open token was TemplateBrace.
  while true {
    lexer.pos += 1
    if lexer.pos >= lexer.end_idx {
      lexer.syntax_error()
      return
    }
    let ch = lexer.source[lexer.pos]
    if ch == CHAR_DOLLAR &&
      lexer.pos + 1 < lexer.end_idx &&
      lexer.source[lexer.pos + 1] == CHAR_BRACE_OPEN {
      lexer.pos += 1 // pos is on '{'
      if lexer.open_token_stack.length() >= 1024 {
        lexer.syntax_error()
        lexer.bail_parsing()
        return
      } // Guard stack
      lexer.open_token_stack.push({
        token: OpenTokenState::TemplateBrace,
        pos: lexer.pos,
      })
      return // Exit to main loop to parse expression
    }
    if ch == CHAR_BACKTICK {
      if lexer.open_token_stack.is_empty() {
        lexer.syntax_error()
        return
      }
      let open_token = lexer.open_token_stack.pop().unwrap() // Should not panic if logic is correct
      if open_token.token != OpenTokenState::Template {
        lexer.syntax_error()
      }
      return // Exit to main loop
    }
    if ch == CHAR_BACKSLASH {
      lexer.pos += 1 // Skip escaped char
      if lexer.pos >= lexer.end_idx {
        lexer.syntax_error()
        return
      }
    }
    // Newlines are allowed in template strings
  }
}

// Reads until whitespace or punctuator. Updates lexer.pos.
// Returns the char that terminated the read (the ws or punctuator).
// lexer.pos will be ON the terminating char.
///|
pub fn read_to_ws_or_punctuator(lexer : Lexer, initial_ch : UInt16) -> UInt16 {
  let mut ch = initial_ch
  // Assuming lexer.pos is already on initial_ch
  if is_br_or_ws(ch) || is_punctuator(ch) {
    return ch
  }
  while true {
    lexer.pos += 1
    if lexer.pos >= lexer.end_idx {
      return (0 : UInt16) // EOF
    }
    ch = lexer.source[lexer.pos]
    if is_br_or_ws(ch) || is_punctuator(ch) {
      return ch
    }
  }
  return ch
}

///| C: isExpressionKeyword (pos is current, checks preceding)
pub fn is_expression_keyword(lexer: Lexer, at_pos: Int) -> Bool {
  if at_pos < 0 || at_pos >= lexer.source_len { return false }
  let current_char = lexer.source[at_pos]
  if at_pos == 0 { return false } // Needs preceding chars
  let prev_char = lexer.source[at_pos - 1]

  match current_char {
    CHAR_D => // void, yield
      match prev_char {
        CHAR_I => read_preceding_keywordn(lexer, at_pos - 2, word_vo_kw) // vo[id]
        CHAR_L => read_preceding_keywordn(lexer, at_pos - 2, word_yie_kw) // yie[ld]
        _ => false
      }
    CHAR_E => {// else, case, delete, continue
      if at_pos < 1 { return false }
      match prev_char {
        CHAR_S => {// els[e], cas[e]
          if at_pos < 2 { return false }
          let prev_prev_char = lexer.source[at_pos - 2]
          match prev_prev_char {
            CHAR_L => read_preceding_keyword1(lexer, at_pos - 3, CHAR_E) // e[lse]
            CHAR_A => read_preceding_keyword1(lexer, at_pos - 3, CHAR_C) // c[ase]
            _ => false
          }
        }
        CHAR_T => read_preceding_keywordn(lexer, at_pos - 2, word_dele_kw) // dele[te]
        CHAR_U => read_preceding_keywordn(lexer, at_pos - 2, word_contin_kw) // contin[ue] (note: C code has 6, contin has 6, so -2 is correct)
        _ => false
      }}
    CHAR_F => {// instanceof, typeof
      if at_pos < 3 { return false } // Needs "of" + one more char
      if prev_char != CHAR_O || lexer.source[at_pos - 2] != CHAR_E { return false } // ..eo[f]
      let CHAR_BEFORE_EOF = lexer.source[at_pos - 3]
      match CHAR_BEFORE_EOF {
         // C: instan_kw is "instan", full "instanceof" length 10. Keyword ends at 'f'. pos-4 for "instan"
        CHAR_C => read_preceding_keywordn(lexer, at_pos - 4, word_instan_kw) // instan[ceof] 
        CHAR_P => read_preceding_keywordn(lexer, at_pos - 4, word_ty_kw)     // ty[peof]
        _ => false
      }
    }
    CHAR_K => read_preceding_keywordn(lexer, at_pos - 1, word_brea_kw) // brea[k]
    CHAR_N => {// in, return
      read_preceding_keyword1(lexer, at_pos - 1, CHAR_I) || // i[n]
      read_preceding_keywordn(lexer, at_pos - 1, word_retur_kw) // retur[n]
    }
    CHAR_O => read_preceding_keyword1(lexer, at_pos - 1, CHAR_D) // d[o]
    CHAR_R => read_preceding_keywordn(lexer, at_pos - 1, word_debugge_kw) // debugge[r]
    CHAR_T => read_preceding_keywordn(lexer, at_pos - 1, word_awai_kw) // awai[t]
    CHAR_W =>{ // new, throw
      if at_pos < 1 { return false }
      match prev_char {
        CHAR_E => read_preceding_keyword1(lexer, at_pos - 2, CHAR_N) // n[ew]
        CHAR_O => read_preceding_keywordn(lexer, at_pos - 2, word_thr_kw) // thr[ow]
        _ => false
      }
      }
    _ => false
  }
}

///| C: isParenKeyword (curPos is the char *before* '(', so it's the end of keyword)
pub fn is_paren_keyword(lexer : Lexer, at_pos : Int) -> Bool {
  read_preceding_keywordn(lexer, at_pos, word_while_kw) ||
  read_preceding_keywordn(lexer, at_pos, word_for_kw) ||
  read_preceding_keywordn(lexer, at_pos, word_if_kw)
}

///| C: isBreakOrContinue (curPos is end of keyword)
pub fn is_break_or_continue(lexer : Lexer, at_pos : Int) -> Bool {
  if at_pos < 0 || at_pos >= lexer.source_len {
    return false
  }
  match lexer.source[at_pos] {
    CHAR_K => read_preceding_keywordn(lexer, at_pos - 1, word_brea_kw) // brea[k]
    CHAR_E => if at_pos > 0 && lexer.source[at_pos - 1] == CHAR_U {
        read_preceding_keywordn(lexer, at_pos - 2, word_contin_kw) // contin[ue]
      } else {
        false
      }
    _ => false
  }
}

///| C: isExpressionTerminator (curPos is end of potential terminator token)
pub fn is_expression_terminator(lexer : Lexer, at_pos : Int) -> Bool {
  if at_pos < 0 || at_pos >= lexer.source_len {
    return false
  }
  match lexer.source[at_pos] {
    CHAR_GT => at_pos > 0 && lexer.source[at_pos - 1] == CHAR_EQ // =>
    CHAR_SEMICOLON | CHAR_PAREN_CLOSE => true // ';' or ')'
    CHAR_H => read_preceding_keywordn(lexer, at_pos - 1, word_catc_kw) // catc[h]
    CHAR_Y => read_preceding_keywordn(lexer, at_pos - 1, word_finall_kw) // finall[y]
    CHAR_E => read_preceding_keywordn(lexer, at_pos - 1, word_els_kw) // el[s]e (note els_kw is "els")
    _ => false
  }
}