/*
 * The external scanner of the .emet grammar (docs/adr/0170): which newlines
 * separate items.
 *
 * Emet.hpeg has no offside rule. A newline separates the top-level
 * declarations, the bindings of where { } and the alternatives of
 * case ... of { }; it is white space where the tokens show that the line
 * goes on:
 *
 * - inside ( ), [ ] and the { } of a record, and after a line that ends in
 *   an operator, =, ->, ::, ',', ? or : -- the parser cannot take a
 *   separator there, so this scanner is not asked for one;
 * - before a line that starts with |, a binary operator but -, ?, :, where
 *   or -> (after blank lines and lines of comments).
 *
 * The separator is the newline alone; the blank lines and the comments
 * after it are read by the grammar as white space and comments.
 */

#include "tree_sitter/parser.h"

#include <stdbool.h>

enum TokenType { SEPARATOR };

void *tree_sitter_emet_external_scanner_create(void) { return NULL; }

void tree_sitter_emet_external_scanner_destroy(void *payload) { (void)payload; }

unsigned tree_sitter_emet_external_scanner_serialize(void *payload, char *buffer) {
  (void)payload;
  (void)buffer;
  return 0;
}

void tree_sitter_emet_external_scanner_deserialize(void *payload, const char *buffer, unsigned length) {
  (void)payload;
  (void)buffer;
  (void)length;
}

static bool is_id_char(int32_t c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

/* Whether the line at the lexer, after its indentation, goes on the line
 * before. The lexer reads past the first token; the caller has marked the
 * end of its own token. */
static bool continues(TSLexer *lexer) {
  for (;;) {
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t' || lexer->lookahead == '\r') {
      lexer->advance(lexer, false);
    }
    if (lexer->lookahead == '\n') {
      lexer->advance(lexer, false);
      continue;
    }
    if (lexer->lookahead != '-') break;
    lexer->advance(lexer, false);
    if (lexer->lookahead == '>') return true;
    /* a - that is no comment starts a new item */
    if (lexer->lookahead != '-') return false;
    while (lexer->lookahead != '\n' && !lexer->eof(lexer)) lexer->advance(lexer, false);
  }
  if (lexer->eof(lexer)) return false;
  switch (lexer->lookahead) {
    case '|':
    case '+':
    case '*':
    case '/':
    case '%':
    case '<':
    case '>':
    case '&':
    case '?':
      return true;
    case '=':
      /* == goes on; = alone is no operator that reads the newline before it */
      lexer->advance(lexer, false);
      return lexer->lookahead == '=';
    case ':':
      /* : goes on; :: does not */
      lexer->advance(lexer, false);
      return lexer->lookahead != ':';
    case 'w': {
      const char *rest = "here";
      lexer->advance(lexer, false);
      for (const char *p = rest; *p; p++) {
        if (lexer->lookahead != *p) return false;
        lexer->advance(lexer, false);
      }
      return !is_id_char(lexer->lookahead);
    }
    default:
      return false;
  }
}

bool tree_sitter_emet_external_scanner_scan(void *payload, TSLexer *lexer, const bool *valid_symbols) {
  (void)payload;
  if (!valid_symbols[SEPARATOR]) return false;
  while (lexer->lookahead == ' ' || lexer->lookahead == '\t' || lexer->lookahead == '\r') {
    lexer->advance(lexer, true);
  }
  if (lexer->lookahead != '\n') return false;
  lexer->advance(lexer, false);
  lexer->mark_end(lexer);
  if (continues(lexer)) return false;
  lexer->result_symbol = SEPARATOR;
  return true;
}
