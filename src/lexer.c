#include "lexer.h"
#include <stdio.h>
#include <string.h>

// NOTE: MESSING WITH THESE REQUIRES MANUAL ASM DICTIONARY CONSTRUCTION (via lexer.emcc.js base64 decoding)
static const char16_t XPORT[] = { 'x', 'p', 'o', 'r', 't' };
static const char16_t MPORT[] = { 'm', 'p', 'o', 'r', 't' };
static const char16_t LASS[] = { 'l', 'a', 's', 's' };
static const char16_t ROM[] = { 'r', 'o', 'm' };
static const char16_t ETA[] = { 'e', 't', 'a' };
static const char16_t SSERT[] = { 's', 's', 'e', 'r', 't' };
static const char16_t VO[] = { 'v', 'o' };
static const char16_t YIE[] = { 'y', 'i', 'e' };
static const char16_t DELE[] = { 'd', 'e', 'l', 'e' };
static const char16_t INSTAN[] = { 'i', 'n', 's', 't', 'a', 'n' };
static const char16_t TY[] = { 't', 'y' };
static const char16_t RETUR[] = { 'r', 'e', 't', 'u', 'r' };
static const char16_t DEBUGGE[] = { 'd', 'e', 'b', 'u', 'g', 'g', 'e' };
static const char16_t AWAI[] = { 'a', 'w', 'a', 'i' };
static const char16_t THR[] = { 't', 'h', 'r' };
static const char16_t WHILE[] = { 'w', 'h', 'i', 'l', 'e' };
static const char16_t FOR[] = { 'f', 'o', 'r' };
static const char16_t IF[] = { 'i', 'f' };
static const char16_t CATC[] = { 'c', 'a', 't', 'c' };
static const char16_t FINALL[] = { 'f', 'i', 'n', 'a', 'l', 'l' };
static const char16_t ELS[] = { 'e', 'l', 's' };
static const char16_t BREA[] = { 'b', 'r', 'e', 'a' };
static const char16_t CONTIN[] = { 'c', 'o', 'n', 't', 'i', 'n' };
static const char16_t SYNC[] = {'s', 'y', 'n', 'c'};
static const char16_t UNCTION[] = {'u', 'n', 'c', 't', 'i', 'o', 'n'};
static const char16_t OURCE[] = {'o', 'u', 'r', 'c', 'e'};
static const char16_t EFER[] = {'e', 'f', 'e', 'r'};

// Note: parsing is based on the _assumption_ that the source is already valid
bool parse () {
  // stack allocations
  // these are done here to avoid data section \0\0\0 repetition bloat
  // (while gzip fixes this, still better to have ~10KiB ungzipped over ~20KiB)
  OpenToken openTokenStack_[1024];
  Import* dynamicImportStack_[512];

  facade = true;
  hasModuleSyntax = false;
  dynamicImportStackDepth = 0;
  openTokenDepth = 0;
  lastTokenPos = (char16_t*)EMPTY_CHAR;
  lastSlashWasDivision = false;
  parse_error = 0;
  has_error = false;
  openTokenStack = &openTokenStack_[0];
  dynamicImportStack = &dynamicImportStack_[0];
  nextBraceIsClass = false;

  pos = (char16_t*)(source - 1);
  char16_t ch = '\0';
  end = pos + sourceLen;

  // start with a pure "module-only" parser
  while (pos++ < end) {
    ch = *pos;

    if (ch == 32 || ch < 14 && ch > 8)
      continue;

    switch (ch) {
      case 'e':
        if (openTokenDepth == 0 && keywordStart(pos) && memcmp(pos + 1, &XPORT[0], 5 * 2) == 0) {
          tryParseExportStatement();
          // export might have been a non-pure declaration
          if (!facade) {
            lastTokenPos = pos;
            goto mainparse;
          }
        }
        break;
      case 'i':
        if (keywordStart(pos) && memcmp(pos + 1, &MPORT[0], 5 * 2) == 0)
          tryParseImportStatement();
        break;
      case ';':
        break;
      case '/': {
        char16_t next_ch = *(pos + 1);
        if (next_ch == '/') {
          lineComment();
          // dont update lastToken
          continue;
        }
        else if (next_ch == '*') {
          blockComment(true);
          // dont update lastToken
          continue;
        }
        // fallthrough
      }
      default:
        // as soon as we hit a non-module token, we go to main parser
        facade = false;
        pos--;
        goto mainparse; // oh yeahhh
    }
    lastTokenPos = pos;
  }

  if (has_error)
    return false;

  mainparse: while (pos++ < end) {
    ch = *pos;

    if (ch == 32 || ch < 14 && ch > 8)
      continue;

    switch (ch) {
      case 'e':
        if (openTokenDepth == 0 && keywordStart(pos) && memcmp(pos + 1, &XPORT[0], 5 * 2) == 0)
          tryParseExportStatement();
        break;
      case 'i':
        if (keywordStart(pos) && memcmp(pos + 1, &MPORT[0], 5 * 2) == 0)
          tryParseImportStatement();
        break;
      case 'c':
        if (keywordStart(pos) && memcmp(pos + 1, &LASS[0], 4 * 2) == 0 && isBrOrWs(*(pos + 5)))
          nextBraceIsClass = true;
        break;
      case '(':
        openTokenStack[openTokenDepth].token = AnyParen;
        openTokenStack[openTokenDepth++].pos = lastTokenPos;
        break;
      case ')':
        if (openTokenDepth == 0)
          return syntaxError(), false;
        openTokenDepth--;
        if (dynamicImportStackDepth > 0 && openTokenStack[openTokenDepth].token == ImportParen) {
          Import* cur_dynamic_import = dynamicImportStack[dynamicImportStackDepth - 1];
          if (cur_dynamic_import->end == 0)
            cur_dynamic_import->end = lastTokenPos + 1;
          cur_dynamic_import->statement_end = pos + 1;
          dynamicImportStackDepth--;
        }
        break;
      case '{':
        // dynamic import followed by { is not a dynamic import (so remove)
        // this is a sneaky way to get around { import () {} } v { import () }
        // block / object ambiguity without a parser (assuming source is valid)
        if (*lastTokenPos == ')' && import_write_head && import_write_head->end == lastTokenPos) {
          import_write_head = import_write_head_last;
          if (import_write_head)
            import_write_head->next = NULL;
          else
            first_import = NULL;
        }
        openTokenStack[openTokenDepth].token = nextBraceIsClass ? ClassBrace : AnyBrace;
        openTokenStack[openTokenDepth++].pos = lastTokenPos;
        nextBraceIsClass = false;
        break;
      case '}':
        if (openTokenDepth == 0)
          return syntaxError(), false;
        if (openTokenStack[--openTokenDepth].token == TemplateBrace) {
          templateString();
        }
        break;
      case '\'':
        stringLiteral(ch);
        break;
      case '"':
        stringLiteral(ch);
        break;
      case '/': {
        char16_t next_ch = *(pos + 1);
        if (next_ch == '/') {
          lineComment();
          // dont update lastToken
          continue;
        }
        else if (next_ch == '*') {
          blockComment(true);
          // dont update lastToken
          continue;
        }
        else {
          // Division / regex ambiguity handling based on checking backtrack analysis of:
          // - what token came previously (lastToken)
          // - if a closing brace or paren, what token came before the corresponding
          //   opening brace or paren (lastOpenTokenIndex)
          char16_t lastToken = *lastTokenPos;
          if (isExpressionPunctuator(lastToken) &&
              !(lastToken == '.' && (*(lastTokenPos - 1) >= '0' && *(lastTokenPos - 1) <= '9')) &&
              !(lastToken == '+' && *(lastTokenPos - 1) == '+') && !(lastToken == '-' && *(lastTokenPos - 1) == '-') ||
              lastToken == ')' && isParenKeyword(openTokenStack[openTokenDepth].pos) ||
              openTokenDepth > 0 && openTokenStack[openTokenDepth - 1].token == AnyParen && *(lastTokenPos) == 'f' && *(lastTokenPos - 1) == 'o' && readPrecedingKeywordn(openTokenStack[openTokenDepth - 1].pos, &FOR[0], 3) ||
              lastToken == '}' && (isExpressionTerminator(openTokenStack[openTokenDepth].pos) || openTokenStack[openTokenDepth].token == ClassBrace) ||
              isExpressionKeyword(lastTokenPos) ||
              lastToken == '/' && lastSlashWasDivision ||
              !lastToken) {
            regularExpression();
            lastSlashWasDivision = false;
          }
          else if (export_write_head != NULL && lastTokenPos >= export_write_head->start && lastTokenPos <= export_write_head->end) {
            // export default /some-regexp/
            regularExpression();
            lastSlashWasDivision = false;
          }
          else {
            // Final check - if the last token was "break x" or "continue x"
            while (lastTokenPos > source && !isBrOrWsOrPunctuatorNotDot(*(--lastTokenPos)));
            if (isWsNotBr(*lastTokenPos)) {
              while (lastTokenPos > source && isWsNotBr(*(--lastTokenPos)));
              if (isBreakOrContinue(lastTokenPos)) {
                regularExpression();
                lastSlashWasDivision = false;
                break;
              }
            }
            lastSlashWasDivision = true;
          }
        }
        break;
      }
      case '`':
        openTokenStack[openTokenDepth].pos = lastTokenPos;
        openTokenStack[openTokenDepth++].token = Template;
        templateString();
        break;
    }
    lastTokenPos = pos;
  }

  if (openTokenDepth || has_error || dynamicImportStackDepth)
    return false;

  // succeess
  return true;
}

void tryParseImportStatement () {
  char16_t* startPos = pos;

  pos += 6;

  char16_t ch = commentWhitespace(true);

  char16_t* maybePhasePos = pos;

  int phase_keyword = 0;

  if (ch == '.') {
    // import.meta
    pos++;
    ch = commentWhitespace(true);
    // import.meta indicated by d == -2
    if (ch == 'm' && memcmp(pos + 1, &ETA[0], 3 * 2) == 0 && (isSpread(lastTokenPos) || *lastTokenPos != '.')) {
      addImport(startPos, startPos, pos + 4, IMPORT_META);
      return;
    }
    else if (ch == 's' && memcmp(pos + 1, &OURCE[0], 5 * 2) == 0 && (isSpread(lastTokenPos) || *lastTokenPos != '.')) {
      phase_keyword = 1;
      pos += 6;
      ch = commentWhitespace(true);
    }
    else if (ch == 'd' && memcmp(pos + 1, &EFER[0], 4 * 2) == 0 && (isSpread(lastTokenPos) || *lastTokenPos != '.')) {
      phase_keyword = 2;
      pos += 5;
      ch = commentWhitespace(true);
    }
    else {
      return;
    }
  }
  else if (pos > startPos + 6 && ch == 's' && memcmp(pos + 1, &OURCE[0], 5 * 2) == 0 && isBrOrWs(*(pos + 6))) {
    phase_keyword = 1;
    pos += 6;
    ch = commentWhitespace(true);
    // need a space after the source keyword, and must not be followed by from keyword
    if (pos == maybePhasePos + 6 || ch == 'f' && memcmp(pos + 1, &ROM[0], 3 * 2) == 0 && isBrOrWsOrPunctuatorNotDot(*(pos + 4))) {
      pos = maybePhasePos;
      phase_keyword = 0;
    }
  }
  else if (pos > startPos + 5 && ch == 'd' && memcmp(pos + 1, &EFER[0], 4 * 2) == 0 && isBrOrWs(*(pos + 5))) {
    phase_keyword = 2;
    pos += 5;
    ch = commentWhitespace(true);
    // need a * after the defer keyword
    if (ch != '*') {
      pos = maybePhasePos;
      phase_keyword = 0;
    }
  }

  // dynamic import
  if (ch == '(') {
    openTokenStack[openTokenDepth].token = ImportParen;
    openTokenStack[openTokenDepth++].pos = pos;
    if (*lastTokenPos == '.')
      return;
    // dynamic import indicated by positive d
    char16_t* dynamicPos = pos;
    // try parse a string, to record a safe dynamic import string
    pos++;
    ch = commentWhitespace(true);
    addImport(startPos, pos, 0, dynamicPos);
    if (phase_keyword > 0)
      import_write_head->import_ty = phase_keyword == 1 ? DynamicSourcePhase : DynamicDeferPhase;
    dynamicImportStack[dynamicImportStackDepth++] = import_write_head;
    if (ch == '\'') {
      stringLiteral(ch);
    }
    else if (ch == '"') {
      stringLiteral(ch);
    }
    else {
      pos--;
      return;
    }
    pos++;
    char16_t* endPos = pos;
    ch = commentWhitespace(true);
    if (ch == ',') {
      pos++;
      ch = commentWhitespace(true);
      import_write_head->end = endPos;
      import_write_head->assert_index = pos;
      import_write_head->safe = true;
      pos--;
    }
    else if (ch == ')') {
      openTokenDepth--;
      import_write_head->end = endPos;
      import_write_head->statement_end = pos + 1;
      import_write_head->safe = true;
      dynamicImportStackDepth--;
    }
    else {
      pos--;
    }
    return;
  }

  if (ch == '{' && phase_keyword == 0) {
    // import statement only permitted at base-level
    if (openTokenDepth != 0) {
      pos--;
      return;
    }

    while (pos < end) {
      ch = commentWhitespace(true);
      if (isQuote(ch)) {
        stringLiteral(ch);
      } else if (ch == '}') {
        pos++;
        break;
      }
      pos++;
    }

    ch = commentWhitespace(true);
    if (ch == 'f' && memcmp(pos + 1, &ROM[0], 3 * 2) != 0) {
      syntaxError();
      return;
    }

    pos += 4;
    ch = commentWhitespace(true);

    if (!isQuote(ch)) {
      return syntaxError();
    }

    readImportString(startPos, ch, false);
  }
  else {
    if (!(ch == '"' || ch == '\'' || ch == '*')) {
      // no space after "import" -> not an import keyword
      if (pos == startPos + 6) {
        pos--;
        return;
      }
    }
    // import defer * as foo mandates *;
    // import statement only permitted at base-level
    if (phase_keyword == 2 && ch != '*' || openTokenDepth != 0) {
      pos--;
      return;
    }
    while (pos < end) {
      ch = *pos;
      if (isQuote(ch)) {
        readImportString(startPos, ch, phase_keyword);
        return;
      }
      pos++;
    }
    syntaxError();
  }
}

void tryParseExportStatement () {
  char16_t* sStartPos = pos;
  Export* prev_export_write_head = export_write_head;

  pos += 6;

  char16_t* curPos = pos;

  char16_t ch = commentWhitespace(true);

  if (pos == curPos && !isPunctuator(ch))
    return;

  if (ch == '{') {
    pos++;
    ch = commentWhitespace(true);
    while (true) {
      char16_t* startPos = pos;

      if (!isQuote(ch)) {
        ch = readToWsOrPunctuator(ch);
      }
      // export { "identifer" as } from
      // export { "@notid" as } from
      // export { "spa ce" as } from
      // export { " space" as } from
      // export { "space " as } from
      // export { "not~id" as } from
      // export { "%notid" as } from
      // export { "identifer" } from
      // export { "%notid" } from
      else {
        stringLiteral(ch);
        pos++;
      }

      char16_t* endPos = pos;
      commentWhitespace(true);
      ch = readExportAs(startPos, endPos);
      // ,
      if (ch == ',') {
        pos++;
        ch = commentWhitespace(true);
      }
      if (ch == '}')
        break;
      if (pos == startPos)
        return syntaxError();
      if (pos > end)
        return syntaxError();
    }
    hasModuleSyntax = true; // to handle "export {}"
    pos++;
    ch = commentWhitespace(true);
  }
  // export *
  // export * as X
  else if (ch == '*') {
    pos++;
    commentWhitespace(true);
    ch = readExportAs(pos, pos);
    ch = commentWhitespace(true);
  }
  else {
    facade = false;
    switch (ch) {
      // export default ...
      case 'd': {
        const char16_t* startPos = pos;
        pos += 7;
        ch = commentWhitespace(true);
        bool localName = false;
        switch (ch) {
          // export default async? function*? name? (){}
          case 'a':
            if (memcmp(pos + 1, &SYNC[0], 4 * 2) == 0 && isWsNotBr(*(pos + 5))) {
              pos += 5;
              ch = commentWhitespace(false);
            }
            else {
              break;
            }
          // fallthrough
          case 'f':
            if (memcmp(pos + 1, &UNCTION[0], 7 * 2) == 0 && (isBrOrWs(*(pos + 8)) || *(pos + 8) == '*' || *(pos + 8) == '(')) {
              pos += 8;
              ch = commentWhitespace(true);
              if (ch == '*') {
                pos++;
                ch = commentWhitespace(true);
              }
              if (ch == '(') {
                break;
              }
              localName = true;
            }
            break;
          case 'c':
            // export default class name? {}
            if (memcmp(pos + 1, &LASS[0], 4 * 2) == 0 && (isBrOrWs(*(pos + 5)) || *(pos + 5) == '{')) {
              pos += 5;
              ch = commentWhitespace(true);
              if (ch == '{') {
                break;
              }
              localName = true;
            }
            break;
        }
        if (localName) {
          const char16_t* localStartPos = pos;
          readToWsOrPunctuator(ch);
          if (pos > localStartPos) {
            addExport(startPos, startPos + 7, localStartPos, pos);
            pos--;
            return;
          }
        }
        addExport(startPos, startPos + 7, NULL, NULL);
        pos = (char16_t*)(startPos + 6);
        return;
      }
      // export async? function*? name () {
      case 'a':
        pos += 5;
        commentWhitespace(false);
      // fallthrough
      case 'f':
        pos += 8;
        ch = commentWhitespace(true);
        if (ch == '*') {
          pos++;
          ch = commentWhitespace(true);
        }
        const char16_t* startPos = pos;
        ch = readToWsOrPunctuator(ch);
        addExport(startPos, pos, startPos, pos);
        pos--;
        return;

      // export class name ...
      case 'c':
        if (memcmp(pos + 1, &LASS[0], 4 * 2) == 0 && isBrOrWsOrPunctuatorNotDot(*(pos + 5))) {
          pos += 5;
          ch = commentWhitespace(true);
          const char16_t* startPos = pos;
          ch = readToWsOrPunctuator(ch);
          addExport(startPos, pos, startPos, pos);
          pos--;
          return;
        }
        pos += 2;
      // fallthrough

      // export var/let/const name = ...(, name = ...)+
      case 'v':
      case 'l':
        // simple declaration lexing only handles names. Any syntax after variable equals is skipped
        // (export var p = function () { ... }, q = 5 skips "q")
        pos += 3;
        facade = false;
        ch = commentWhitespace(true);
        startPos = pos;
        ch = readToWsOrPunctuator(ch);
        // very basic destructuring support only of the singular form:
        //   export const { a, b, ...c }
        // without aliasing, nesting or defaults
        bool destructuring = ch == '{' || ch == '[';
        const char16_t* destructuringPos = pos;
        if (destructuring) {
          pos += 1;
          ch = commentWhitespace(true);
          startPos = pos;
          ch = readToWsOrPunctuator(ch);
        }
        do {
          if (pos == startPos)
            break;
          addExport(startPos, pos, startPos, pos);
          ch = commentWhitespace(true);
          if (destructuring && (ch == '}' || ch == ']')) {
            destructuring = false;
            break;
          }
          if (ch != ',') {
            pos -= 1;
            break;
          }
          pos++;
          ch = commentWhitespace(true);
          startPos = pos;
          // internal destructurings unsupported
          if (ch == '{' || ch == '[') {
            pos -= 1;
            break;
          }
          ch = readToWsOrPunctuator(ch);
        } while (true);
        // if stuck inside destructuring syntax, backtrack
        if (destructuring) {
          pos = (char16_t*)destructuringPos - 1;
        }
        return;

      default:
        return;
    }
  }

  // from ...
  if (ch == 'f' && memcmp(pos + 1, &ROM[0], 3 * 2) == 0) {
    pos += 4;
    readImportString(sStartPos, commentWhitespace(true), false);

    // There were no local names.
    for (Export* exprt = prev_export_write_head == NULL ? first_export : prev_export_write_head->next; exprt != NULL; exprt = exprt->next) {
      exprt->local_start = exprt->local_end = NULL;
    }
  }
  else {
    pos--;
  }
}

char16_t readExportAs (char16_t* startPos, char16_t* endPos) {
  char16_t ch = *pos;
  char16_t* localStartPos = startPos == endPos ? NULL : startPos;
  char16_t* localEndPos = startPos == endPos ? NULL : endPos;

  if (ch == 'a') {
    pos += 2;
    ch = commentWhitespace(true);
    startPos = pos;

    if (!isQuote(ch)) {
      ch = readToWsOrPunctuator(ch);
    }
    // export { mod as "identifer" } from
    // export { mod as "@notid" } from
    // export { mod as "spa ce" } from
    // export { mod as " space" } from
    // export { mod as "space " } from
    // export { mod as "not~id" } from
    // export { mod as "%notid" } from
    else {
      stringLiteral(ch);
      pos++;
    }

    endPos = pos;

    ch = commentWhitespace(true);
  }

  if (pos != startPos)
    addExport(startPos, endPos, localStartPos, localEndPos);
  return ch;
}

void readImportString (const char16_t* ss, char16_t ch, int phase_keyword) {
  const char16_t* startPos = pos + 1;
  if (ch == '\'') {
    stringLiteral(ch);
  }
  else if (ch == '"') {
    stringLiteral(ch);
  }
  else {
    syntaxError();
    return;
  }
  addImport(ss, startPos, pos, STANDARD_IMPORT);
  if (phase_keyword > 0) {
    import_write_head->import_ty = phase_keyword == 1 ? StaticSourcePhase : StaticDeferPhase;
  }
  pos++;
  ch = commentWhitespace(false);
  if (!(ch == 'a' && memcmp(pos + 1, &SSERT[0], 5 * 2) == 0) && !(ch == 'w' && *(pos + 1) == 'i' && *(pos + 2) == 't' && *(pos + 3) == 'h')) {
    pos--;
    return;
  }
  char16_t* assertIndex = pos;
  pos += ch == 'a' ? 6 : 4;
  ch = commentWhitespace(true);
  if (ch != '{') {
    pos = assertIndex;
    return;
  }
  const char16_t* assertStart = pos;
  do {
    pos++;
    ch = commentWhitespace(true);
    if (ch == '\'') {
      stringLiteral(ch);
      pos++;
      ch = commentWhitespace(true);
    }
    else if (ch == '"') {
      stringLiteral(ch);
      pos++;
      ch = commentWhitespace(true);
    }
    else {
      ch = readToWsOrPunctuator(ch);
    }
    if (ch != ':') {
      pos = assertIndex;
      return;
    }
    pos++;
    ch = commentWhitespace(true);
    if (ch == '\'') {
      stringLiteral(ch);
    }
    else if (ch == '"') {
      stringLiteral(ch);
    }
    else {
      pos = assertIndex;
      return;
    }
    pos++;
    ch = commentWhitespace(true);
    if (ch == ',') {
      pos++;
      ch = commentWhitespace(true);
      if (ch == '}')
        break;
      continue;
    }
    if (ch == '}')
      break;
    pos = assertIndex;
    return;
  } while (true);
  import_write_head->assert_index = assertStart;
  import_write_head->statement_end = pos + 1;
}

char16_t commentWhitespace (bool br) {
  char16_t ch;
  do {
    ch = *pos;
    if (ch == '/') {
      char16_t next_ch = *(pos + 1);
      if (next_ch == '/')
        lineComment();
      else if (next_ch == '*')
        blockComment(br);
      else
        return ch;
    }
    else if (br ? !isBrOrWs(ch) : !isWsNotBr(ch)) {
      return ch;
    }
  } while (pos++ < end);
  return ch;
}

void templateString () {
  while (pos++ < end) {
    char16_t ch = *pos;
    if (ch == '$' && *(pos + 1) == '{') {
      pos++;
      openTokenStack[openTokenDepth].token = TemplateBrace;
      openTokenStack[openTokenDepth++].pos = pos;
      return;
    }
    if (ch == '`') {
      if (openTokenStack[--openTokenDepth].token != Template)
        syntaxError();
      return;
    }
    if (ch == '\\')
      pos++;
  }
  syntaxError();
}

void blockComment (bool br) {
  pos++;
  while (pos++ < end) {
    char16_t ch = *pos;
    if (!br && isBr(ch))
      return;
    if (ch == '*' && *(pos + 1) == '/') {
      pos++;
      return;
    }
  }
}

void lineComment () {
  while (pos++ < end) {
    char16_t ch = *pos;
    if (ch == '\n' || ch == '\r')
      return;
  }
}

void stringLiteral (char16_t quote) {
  while (pos++ < end) {
    char16_t ch = *pos;
    if (ch == quote)
      return;
    if (ch == '\\') {
      ch = *++pos;
      if (ch == '\r' && *(pos + 1) == '\n')
        pos++;
    }
    else if (isBr(ch))
      break;
  }
  syntaxError();
}

char16_t regexCharacterClass () {
  while (pos++ < end) {
    char16_t ch = *pos;
    if (ch == ']')
      return ch;
    if (ch == '\\')
      pos++;
    else if (ch == '\n' || ch == '\r')
      break;
  }
  syntaxError();
  return '\0';
}

void regularExpression () {
  while (pos++ < end) {
    char16_t ch = *pos;
    if (ch == '/')
      return;
    if (ch == '[')
      ch = regexCharacterClass();
    else if (ch == '\\')
      pos++;
    else if (ch == '\n' || ch == '\r')
      break;
  }
  syntaxError();
}

char16_t readToWsOrPunctuator (char16_t ch) {
  do {
    if (isBrOrWs(ch) || isPunctuator(ch))
      return ch;
  } while (ch = *(++pos));
  return ch;
}

// Note: non-asii BR and whitespace checks omitted for perf / footprint
// if there is a significant user need this can be reconsidered
bool isBr (char16_t c) {
  return c == '\r' || c == '\n';
}

bool isWsNotBr (char16_t c) {
  return c == 9 || c == 11 || c == 12 || c == 32 || c == 160;
}

bool isBrOrWs (char16_t c) {
  return c > 8 && c < 14 || c == 32 || c == 160;
}

bool isBrOrWsOrPunctuatorNotDot (char16_t c) {
  return c > 8 && c < 14 || c == 32 || c == 160 || isPunctuator(c) && c != '.';
}

bool isBrOrWsOrPunctuatorOrSpreadNotDot (char16_t* c) {
  return *c > 8 && *c < 14 || *c == 32 || *c == 160 || isPunctuator(*c) && (isSpread(c) || *c != '.');
}

bool isSpread (char16_t* c) {
  return *c == '.' && *(c - 1) == '.' && *(c - 2) == '.';
}

bool isQuote (char16_t ch) {
  return ch == '\'' || ch == '"';
}

bool keywordStart (char16_t* pos) {
  return pos == source || isBrOrWsOrPunctuatorOrSpreadNotDot(pos - 1);
}

bool readPrecedingKeyword1 (char16_t* pos, char16_t c1) {
  if (pos < source) return false;
  return *pos == c1 && (pos == source || isBrOrWsOrPunctuatorNotDot(*(pos - 1)));
}

bool readPrecedingKeywordn (char16_t* pos, const char16_t* compare, size_t n) {
  if (pos - n + 1 < source) return false;
  return memcmp(pos - n + 1, compare, n * 2) == 0 && (pos - n + 1 == source || isBrOrWsOrPunctuatorOrSpreadNotDot(pos - n));
}

// Detects one of case, debugger, delete, do, else, in, instanceof, new,
//   return, throw, typeof, void, yield ,await
bool isExpressionKeyword (char16_t* pos) {
  switch (*pos) {
    case 'd':
      switch (*(pos - 1)) {
        case 'i':
          // void
          return readPrecedingKeywordn(pos - 2, &VO[0], 2);
        case 'l':
          // yield
          return readPrecedingKeywordn(pos - 2, &YIE[0], 3);
        default:
          return false;
      }
    case 'e':
      switch (*(pos - 1)) {
        case 's':
          switch (*(pos - 2)) {
            case 'l':
              // else
              return readPrecedingKeyword1(pos - 3, 'e');
            case 'a':
              // case
              return readPrecedingKeyword1(pos - 3, 'c');
            default:
              return false;
          }
        case 't':
          // delete
          return readPrecedingKeywordn(pos - 2, &DELE[0], 4);
        case 'u':
          // continue
          return readPrecedingKeywordn(pos - 2, &CONTIN[0], 6);
        default:
          return false;
      }
    case 'f':
      if (*(pos - 1) != 'o' || *(pos - 2) != 'e')
        return false;
      switch (*(pos - 3)) {
        case 'c':
          // instanceof
          return readPrecedingKeywordn(pos - 4, &INSTAN[0], 6);
        case 'p':
          // typeof
          return readPrecedingKeywordn(pos - 4, &TY[0], 2);
        default:
          return false;
      }
    case 'k':
      // break
      return readPrecedingKeywordn(pos - 1, &BREA[0], 4);
    case 'n':
      // in, return
      return readPrecedingKeyword1(pos - 1, 'i') || readPrecedingKeywordn(pos - 1, &RETUR[0], 5);
    case 'o':
      // do
      return readPrecedingKeyword1(pos - 1, 'd');
    case 'r':
      // debugger
      return readPrecedingKeywordn(pos - 1, &DEBUGGE[0], 7);
    case 't':
      // await
      return readPrecedingKeywordn(pos - 1, &AWAI[0], 4);
    case 'w':
      switch (*(pos - 1)) {
        case 'e':
          // new
          return readPrecedingKeyword1(pos - 2, 'n');
        case 'o':
          // throw
          return readPrecedingKeywordn(pos - 2, &THR[0], 3);
        default:
          return false;
      }
  }
  return false;
}

bool isParenKeyword (char16_t* curPos) {
  return readPrecedingKeywordn(curPos, &WHILE[0], 5) ||
      readPrecedingKeywordn(curPos, &FOR[0], 3) ||
      readPrecedingKeywordn(curPos, &IF[0], 2);
}

bool isPunctuator (char16_t ch) {
  // 23 possible punctuator endings: !%&()*+,-./:;<=>?[]^{}|~
  return ch == '!' || ch == '%' || ch == '&' ||
    ch > 39 && ch < 48 || ch > 57 && ch < 64 ||
    ch == '[' || ch == ']' || ch == '^' ||
    ch > 122 && ch < 127;
}

bool isExpressionPunctuator (char16_t ch) {
  // 20 possible expression endings: !%&(*+,-.:;<=>?[^{|~
  return ch == '!' || ch == '%' || ch == '&' ||
    ch > 39 && ch < 47 && ch != 41 || ch > 57 && ch < 64 ||
    ch == '[' || ch == '^' || ch > 122 && ch < 127 && ch != '}';
}

bool isBreakOrContinue (char16_t* curPos) {
  switch (*curPos) {
    case 'k':
      return readPrecedingKeywordn(curPos - 1, &BREA[0], 4);
    case 'e':
      if (*(curPos - 1) == 'u')
        return readPrecedingKeywordn(curPos - 2, &CONTIN[0], 6);
  }
  return false;
}

bool isExpressionTerminator (char16_t* curPos) {
  // detects:
  // => ; ) finally catch else class X
  // as all of these followed by a { will indicate a statement brace
  switch (*curPos) {
    case '>':
      return *(curPos - 1) == '=';
    case ';':
    case ')':
      return true;
    case 'h':
      return readPrecedingKeywordn(curPos - 1, &CATC[0], 4);
    case 'y':
      return readPrecedingKeywordn(curPos - 1, &FINALL[0], 6);
    case 'e':
      return readPrecedingKeywordn(curPos - 1, &ELS[0], 3);
  }
  return false;
}

void bail (uint32_t error) {
  has_error = true;
  parse_error = error;
  pos = end + 1;
}

void syntaxError () {
  has_error = true;
  parse_error = pos - source;
  pos = end + 1;
}
