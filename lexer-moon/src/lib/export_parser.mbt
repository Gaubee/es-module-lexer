///|
fn add_export(
  lexer : Lexer,
  name_start : Int,
  name_end : Int,
  local_name_start : Int?,
  local_name_end : Int?
) -> Unit {
  if lexer.exports.length() >= 512 {
    lexer.syntax_error()
    lexer.bail_parsing()
    return
  }
  let new_export = {
    start: name_start,
    end: name_end,
    local_start: local_name_start,
    local_end: local_name_end,
  }
  lexer.exports.push(new_export)
  lexer.has_module_syntax = true
}

// Corresponds to readExportAs
// lexer.pos is on the char to check for 'as'
// start_pos_arg, end_pos_arg refer to the first identifier (local if 'as' is present, exported otherwise)
///|
fn read_export_as(
  lexer : Lexer,
  start_pos_arg : Int,
  end_pos_arg : Int
) -> UInt16 {
  let mut ch = lexer.source[lexer.pos]
  let mut local_s : Int? = if start_pos_arg == end_pos_arg {
    None
  } else {
    Some(start_pos_arg)
  }
  let mut local_e : Int? = if start_pos_arg == end_pos_arg {
    None
  } else {
    Some(end_pos_arg)
  }
  let mut exported_s : Int = start_pos_arg
  let mut exported_e : Int = end_pos_arg
  if ch == CHAR_A && source_matches(lexer, lexer.pos + 1, word_s_kw) { // "as"
    lexer.pos += 2 // "as"
    ch = comment_whitespace(lexer, true)
    if lexer.has_error {
      return (0 : UInt16)
    }
    exported_s = lexer.pos
    if is_quote(ch) {
      string_literal(lexer, ch) // pos is on closing quote
      if lexer.has_error {
        return (0 : UInt16)
      }
      lexer.pos += 1 // past quote
    } else {
      ch = read_to_ws_or_punctuator(lexer, ch) // pos is on ws/punc
      if lexer.has_error {
        return (0 : UInt16)
      }
    }
    exported_e = lexer.pos // end is exclusive for read_to, inclusive for string_literal then +1
    ch = comment_whitespace(lexer, true) // Read char after exported name
    if lexer.has_error {
      return (0 : UInt16)
    }
  } else {
    // No "as", so local_s/e are None, start_pos_arg/end_pos_arg are the exported names
    local_s = None
    local_e = None
  }
  if exported_s != exported_e { // If a name was actually read
    add_export(lexer, exported_s, exported_e, local_s, local_e)
  }
  return if lexer.pos < lexer.source_len {
    lexer.source[lexer.pos]
  } else {
    (0 : UInt16)
  }
}

pub fn try_parse_export_statement(lexer: Lexer)->Unit {
  let statement_start_pos = lexer.pos // on 'e' of "export"
  let num_exports_before = lexer.exports.length()

  lexer.pos += 6 // "export"
  
  let cur_pos_after_export = lexer.pos
  let mut ch = comment_whitespace(lexer, true)
  if lexer.has_error { return }

  if cur_pos_after_export == lexer.pos && not(is_punctuator(ch)) {
    // "export" not followed by space or punctuator, e.g. "exportFoo"
    lexer.pos = statement_start_pos // backtrack
    return
  }

  if ch == CHAR_BRACE_OPEN { // export { ... }
    lexer.pos += 1 // Skip '{'
    ch = comment_whitespace(lexer, true)
    if lexer.has_error { return }
    
    while true {
      let id_start_pos = lexer.pos
      if is_quote(ch) {
        string_literal(lexer, ch) // pos on closing quote
        if lexer.has_error { return }
        lexer.pos += 1 // past quote
      } else {
        ch = read_to_ws_or_punctuator(lexer, ch) // pos on ws/punc
        if lexer.has_error { return }
      }
      let id_end_pos = lexer.pos

      ch = comment_whitespace(lexer, true) // To position for read_export_as
      if lexer.has_error { return }
      ch = read_export_as(lexer, id_start_pos, id_end_pos) // Consumes 'as name', updates ch
      if lexer.has_error { return }

      if ch == CHAR_COMMA {
        lexer.pos += 1
        ch = comment_whitespace(lexer, true)
        if lexer.has_error { return }
      } else if ch == CHAR_BRACE_CLOSE {
        break
      } else {
        lexer.syntax_error(); return // Expected comma or }
      }
      if lexer.pos == id_start_pos { lexer.syntax_error(); return } // No progress
      if lexer.pos > lexer.end_idx { lexer.syntax_error(); return } // EOF
    }
    lexer.has_module_syntax = true // Handle "export {}"
    lexer.pos += 1 // Skip '}'
    ch = comment_whitespace(lexer, true)
    if lexer.has_error { return }

  } else if ch == CHAR_ASTERISK { // export * ...
    lexer.pos += 1 // Skip '*'
    ch = comment_whitespace(lexer, true) // To position for read_export_as
    if lexer.has_error { return }
    ch = read_export_as(lexer, lexer.pos, lexer.pos) // No local name for export *
    if lexer.has_error { return }
    ch = comment_whitespace(lexer, true) // Read char after potential 'as X'
    if lexer.has_error { return }

  } else { // export default, export var/let/const, export function, export class
    lexer.facade = false // These are declarations, not pure module syntax
    match ch {
      CHAR_D => { // "default"
        if not(source_matches(lexer, lexer.pos, word_default_kw)) { lexer.pos = statement_start_pos; return }
        let default_keyword_start_pos = lexer.pos
        lexer.pos += 7 // "default"
        ch = comment_whitespace(lexer, true)
        if lexer.has_error { return }

        let mut local_name = false
        let mut decl_start_pos = lexer.pos
        match ch {
          CHAR_A => { // async function
            if source_matches(lexer, lexer.pos + 1, word_sync_kw) && is_br_or_ws(lexer.source[lexer.pos + 5]) {
              lexer.pos += 5 // "async"
              ch = comment_whitespace(lexer, false) // space is part of it
              if lexer.has_error { return }
              // Fallthrough to 'f' for function
            } else { 
              // not 'async function', break to default export handling */
             }
          }
          CHAR_F => { // function or (after async) function
            if source_matches(lexer, lexer.pos + 1, word_unction_kw) && 
               (is_br_or_ws(lexer.source[lexer.pos+8]) || lexer.source[lexer.pos+8] == CHAR_ASTERISK || lexer.source[lexer.pos+8] == '('.to_int().to_uint16()) {
              lexer.pos += 8 // "function"
              ch = comment_whitespace(lexer, true)
              if lexer.has_error { return }
              if ch == CHAR_ASTERISK {
                lexer.pos += 1
                ch = comment_whitespace(lexer, true)
                if lexer.has_error { return }
              }
              if ch != '('.to_int().to_uint16() { local_name = true } // If not '(', then there's a name
            }
          }
          CHAR_C => { // class
            if source_matches(lexer, lexer.pos + 1, word_lass_kw) &&
               (is_br_or_ws(lexer.source[lexer.pos+5]) || lexer.source[lexer.pos+5] == CHAR_BRACE_OPEN) {
              lexer.pos += 5 // "class"
              ch = comment_whitespace(lexer, true)
              if lexer.has_error { return }
              if ch != CHAR_BRACE_OPEN { local_name = true } // If not '{', then there's a name
            }
          }
          _ => {
             // export default [expression]
             ignore("export default [expression]")
            }
        }

        if local_name {
          let local_name_start_pos = lexer.pos
          ch = read_to_ws_or_punctuator(lexer, ch) // Read the name
          if lexer.has_error { return }
          if lexer.pos > local_name_start_pos {
            // export default function Name ...
            // "Name" is local, "default" is exported.
            // C: addExport(startPos, startPos + 7, localStartPos, pos);
            // startPos = default_keyword_start_pos, end = default_keyword_start_pos + 7 ("default")
            // localStart = local_name_start_pos, localEnd = lexer.pos
            add_export(lexer, default_keyword_start_pos, default_keyword_start_pos + 7, Some(local_name_start_pos), Some(lexer.pos))
            lexer.pos -=1 // read_to_ws_or_punctuator goes one past, backtrack.
            return
          }
        }
        // export default (expression | class {} | function () {})
        // "default" is exported, no specific local name from here.
        add_export(lexer, default_keyword_start_pos, default_keyword_start_pos + 7, None, None)
        lexer.pos = default_keyword_start_pos + 6 // backtrack to end of "default"
        return
      }
      CHAR_A => { // "async" function
        if not(source_matches(lexer, lexer.pos, word_async_kw)) { lexer.pos = statement_start_pos; return }
        lexer.pos += 5 // "async"
        ch = comment_whitespace(lexer, false) // space is part of it
        if lexer.has_error { return }
        // Fallthrough to 'f'
        ch = lexer.source[lexer.pos] // Re-fetch char
      }
      CHAR_F => { // "function" (or after "async")
        if not(source_matches(lexer, lexer.pos, word_function_kw)) { lexer.pos = statement_start_pos; return }
        lexer.pos += 8 // "function"
        ch = comment_whitespace(lexer, true)
        if lexer.has_error { return }
        if ch == CHAR_ASTERISK {
          lexer.pos += 1
          ch = comment_whitespace(lexer, true)
          if lexer.has_error { return }
        }
        let name_start_pos = lexer.pos
        ch = read_to_ws_or_punctuator(lexer, ch) // Read name
        if lexer.has_error { return }
        add_export(lexer, name_start_pos, lexer.pos, Some(name_start_pos), Some(lexer.pos))
        lexer.pos -= 1; return
      }
      CHAR_C => { // "class" or "const"
        if source_matches(lexer, lexer.pos, word_class_kw) && is_br_or_ws_or_punctuator_not_dot(lexer.source[lexer.pos + 5]) {
          lexer.pos += 5 // "class"
          ch = comment_whitespace(lexer, true)
          if lexer.has_error { return }
          let name_start_pos = lexer.pos
          ch = read_to_ws_or_punctuator(lexer, ch)
          if lexer.has_error { return }
          add_export(lexer, name_start_pos, lexer.pos, Some(name_start_pos), Some(lexer.pos))
          lexer.pos -= 1; return
        } else if source_matches(lexer, lexer.pos, word_const_kw) {
           lexer.pos += 5 // "const"
           // Fallthrough to var/let/const common logic
        } else { lexer.pos = statement_start_pos; return }
      }
      CHAR_V => { // "var"
         if not(source_matches(lexer, lexer.pos, word_var_kw)) { lexer.pos = statement_start_pos; return }
         lexer.pos += 3 // "var"
         // Fallthrough
      }
      CHAR_L => { // "let"
         if not(source_matches(lexer, lexer.pos, word_let_kw)) { lexer.pos = statement_start_pos; return }
         lexer.pos += 3 // "let"
         // Fallthrough for var/let/const
      }
      _ => { lexer.pos = statement_start_pos; return } // Not a recognized export declaration form
    }
    // Common logic for var/let/const
    lexer.facade = false // C code sets this again
    ch = comment_whitespace(lexer, true)
    if lexer.has_error { return }

    let mut name_start_pos = lexer.pos
    ch = read_to_ws_or_punctuator(lexer, ch) // read first char, ch becomes terminator
    if lexer.has_error { return }
    
    let mut is_destructuring = ch == CHAR_BRACE_OPEN || ch == CHAR_BRACKET_OPEN
    let destructuring_start_lexer_pos = lexer.pos // pos is on { or [

    if is_destructuring {
      lexer.pos += 1 // Skip { or [
      ch = comment_whitespace(lexer, true)
      if lexer.has_error { return }
      name_start_pos = lexer.pos // First name inside destructuring
      ch = read_to_ws_or_punctuator(lexer, ch)
      if lexer.has_error { return }
    }

    while true {
      if lexer.pos == name_start_pos && not(is_destructuring) { break } // No name read
      if lexer.pos > name_start_pos { // Name was read
          add_export(lexer, name_start_pos, lexer.pos, Some(name_start_pos), Some(lexer.pos))
      }
      
      ch = comment_whitespace(lexer, true) // After name (or if name_start_pos==lexer.pos, ch is still the { or [)
      if lexer.has_error { return }

      if is_destructuring && (ch == CHAR_BRACE_CLOSE || ch == CHAR_BRACKET_CLOSE) {
        // Ensure matching braces/brackets for basic support
        let open_char = lexer.source[destructuring_start_lexer_pos]
        if (open_char == CHAR_BRACE_OPEN && ch == CHAR_BRACE_CLOSE) || (open_char == CHAR_BRACKET_OPEN && ch == CHAR_BRACKET_CLOSE) {
            is_destructuring = false // Destructuring ended
            lexer.pos +=1 // consume closing } or ]
            ch = comment_whitespace(lexer, true) // check for comma for `export const {a}, b`
                                                // but C code breaks here, so we mimic
            break 
        } else {
            // Mismatched, backtrack and treat as non-destructuring from original point
            lexer.pos = destructuring_start_lexer_pos -1
            // Clear exports added from this failed destructuring attempt
            while lexer.exports.length() > num_exports_before { let _ = lexer.exports.pop() }
            return
        }
      }

      if ch != CHAR_COMMA {
        lexer.pos -=1 // Backtrack if not comma, so main loop sees this char
        break
      }
      lexer.pos +=1 // Skip comma
      ch = comment_whitespace(lexer, true)
      if lexer.has_error { return }
      name_start_pos = lexer.pos
      // C: internal destructurings unsupported: if (ch == '{' || ch == '[') { pos -= 1; break; }
      if is_destructuring && (ch == CHAR_BRACE_OPEN || ch == CHAR_BRACKET_OPEN) {
          lexer.pos -=1; break; // Exit loop, effectively ignoring this part
      }
      ch = read_to_ws_or_punctuator(lexer, ch)
      if lexer.has_error { return }
      if lexer.pos == name_start_pos { break } // No progress after comma
    } // End var/let/const name parsing loop
    
    if is_destructuring { // Stuck inside destructuring (e.g. unclosed)
        lexer.pos = destructuring_start_lexer_pos -1
        while lexer.exports.length() > num_exports_before { let _ = lexer.exports.pop() }
    }
    return // End of var/let/const
  } // End of export type switch (brace, asterisk, declarations)

  // Handle 'from "module"' part, if any
  // ch is the char after export clause (e.g. after '}' of export {x}, or after 'export * as y')
  if ch == CHAR_F && source_matches(lexer, lexer.pos + 1, word_rom_kw) {
    lexer.pos += 4 // "from"
    let quote_char = comment_whitespace(lexer, true)
    if lexer.has_error { return }
    // Use a simplified readImportString variant or direct logic for 'from' string
    if not(is_quote(quote_char)) { lexer.syntax_error(); return }
    
    // This call to read_import_string is problematic because read_import_string ADDS an import.
    // We need to parse the string for the export 'from' clause, not create an import record.
    // C's `readImportString(sStartPos, commentWhitespace(true), false);`
    // `sStartPos` is `statement_start_pos` (start of 'export' keyword).
    // This means C code creates an Import record for `export ... from "mod"`.
    // This is unusual. Let's replicate for now, but flag as review.
    // The boolean `false` for phase_keyword matches C.
    // TODO: Review if `export ... from "string"` should create an `Import` record.
    // For now, assume it's intended for some analysis purpose.
    read_import_string(lexer, statement_start_pos, quote_char, 0)
    if lexer.has_error { return }

    // C: Nullify local_start/local_end for exports from this 'from' clause
    // This means `export {a as b} from "m"` -> exported: "b", local: null
    // If `num_exports_before` is index of first export in this statement:
    for i = num_exports_before; i < lexer.exports.length(); i += 1 {
      let current_export = lexer.exports[i]
      lexer.exports[i] = { current_export with local_start: None, local_end: None }
    }
  } else {
    // Not 'from', backtrack so main loop can see `ch`
    lexer.pos -= 1
  }
}
