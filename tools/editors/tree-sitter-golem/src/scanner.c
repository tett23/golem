/*
 * The external scanner of the .gm grammar (docs/adr/0170): the tokens that
 * depend on the lines around them. See grammar.js for the list.
 *
 * The state is the stack of the indentations of the open bodies, the
 * indentation of the current line, the column where the text of its block
 * starts (two more than the indentation for a list item: - text), and the
 * dedents and the newline still to give after a line that closes bodies.
 */

#include "tree_sitter/parser.h"

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

enum TokenType {
  NEWLINE,
  INDENT,
  DEDENT,
  CONTINUATION,
  PARAGRAPH_START,
  TEXT,
  SLOT_TEXT,
  CELL_TEXT,
  COMMENT,
  PROOF_COMMENT,
  NUMBER_OPEN,
  NUMBER_CLOSE,
  CODE_CONTENT,
  CODE_CLOSE,
  ERROR_SENTINEL,
};

#define MAX_DEPTH 100

typedef struct {
  uint16_t stack[MAX_DEPTH];
  uint8_t depth; /* stack[0] is always 0 */
  uint16_t line_col;
  uint16_t content_col;
  uint8_t pending_dedents;
  bool pending_newline;
} Scanner;

void *tree_sitter_golem_external_scanner_create(void) {
  Scanner *s = calloc(1, sizeof(Scanner));
  s->depth = 1;
  return s;
}

void tree_sitter_golem_external_scanner_destroy(void *payload) { free(payload); }

unsigned tree_sitter_golem_external_scanner_serialize(void *payload, char *buffer) {
  Scanner *s = payload;
  unsigned n = 0;
  buffer[n++] = (char)s->depth;
  buffer[n++] = (char)s->pending_dedents;
  buffer[n++] = (char)s->pending_newline;
  memcpy(buffer + n, &s->line_col, sizeof s->line_col);
  n += sizeof s->line_col;
  memcpy(buffer + n, &s->content_col, sizeof s->content_col);
  n += sizeof s->content_col;
  memcpy(buffer + n, s->stack, s->depth * sizeof s->stack[0]);
  n += s->depth * sizeof s->stack[0];
  return n;
}

void tree_sitter_golem_external_scanner_deserialize(void *payload, const char *buffer, unsigned length) {
  Scanner *s = payload;
  memset(s, 0, sizeof *s);
  s->depth = 1;
  if (length == 0) return;
  unsigned n = 0;
  s->depth = (uint8_t)buffer[n++];
  s->pending_dedents = (uint8_t)buffer[n++];
  s->pending_newline = buffer[n++];
  memcpy(&s->line_col, buffer + n, sizeof s->line_col);
  n += sizeof s->line_col;
  memcpy(&s->content_col, buffer + n, sizeof s->content_col);
  n += sizeof s->content_col;
  memcpy(s->stack, buffer + n, s->depth * sizeof s->stack[0]);
}

static void advance(TSLexer *lexer) { lexer->advance(lexer, false); }

static bool is_space(int32_t c) { return c == ' ' || c == '\t'; }

static bool is_digit(int32_t c) { return c >= '0' && c <= '9'; }

typedef struct {
  bool block_start;
  bool list_marker;
} LineStart;

/* What the line at the lexer starts with (BlockStart of Golem.hpeg): #
 * (but not ##N), - and +, = and =:, |, ```, @name and @!. Only looks: the
 * caller has marked the end of its token. */
static LineStart line_start(TSLexer *lexer) {
  LineStart r = {false, false};
  switch (lexer->lookahead) {
    case '#':
      advance(lexer);
      if (lexer->lookahead != '#') {
        r.block_start = true;
        return r;
      }
      advance(lexer);
      r.block_start = !is_digit(lexer->lookahead);
      return r;
    case '-':
    case '+':
      advance(lexer);
      r.block_start = r.list_marker = is_space(lexer->lookahead);
      return r;
    case '=':
      advance(lexer);
      r.block_start = is_space(lexer->lookahead) || lexer->lookahead == ':';
      return r;
    case '|':
      r.block_start = true;
      return r;
    case '`':
      advance(lexer);
      if (lexer->lookahead != '`') return r;
      advance(lexer);
      r.block_start = lexer->lookahead == '`';
      return r;
    case '@':
      advance(lexer);
      r.block_start = (lexer->lookahead >= 'a' && lexer->lookahead <= 'z') || lexer->lookahead == '!';
      return r;
    default:
      return r;
  }
}

/* The lines of a code block after its opening fence, at the newline that
 * ends that line: the content up to the line before the closing fence (a
 * fence at the indentation of the opening one), or, when that is the next
 * line, the newline and the indentation before the closing fence. */
static bool scan_code(Scanner *s, TSLexer *lexer, const bool *valid) {
  bool content = false;
  for (;;) {
    if (lexer->eof(lexer)) {
      if (!content) return false;
      lexer->result_symbol = CODE_CONTENT;
      return true;
    }
    if (content) lexer->mark_end(lexer);
    advance(lexer); /* the newline */
    unsigned col = 0;
    while (lexer->lookahead == ' ') {
      advance(lexer);
      col++;
    }
    if (!content) lexer->mark_end(lexer);
    if (col == s->line_col && lexer->lookahead == '`') {
      int ticks = 0;
      while (lexer->lookahead == '`' && ticks < 3) {
        advance(lexer);
        ticks++;
      }
      if (ticks == 3) {
        while (is_space(lexer->lookahead) || lexer->lookahead == '\r') advance(lexer);
        if (lexer->lookahead == '\n' || lexer->eof(lexer)) {
          if (content) {
            lexer->result_symbol = CODE_CONTENT;
            return true;
          }
          if (!valid[CODE_CLOSE]) return false;
          lexer->result_symbol = CODE_CLOSE;
          return true;
        }
      }
    }
    if (!valid[CODE_CONTENT]) return false;
    content = true;
    while (lexer->lookahead != '\n' && !lexer->eof(lexer)) advance(lexer);
    if (lexer->eof(lexer)) lexer->mark_end(lexer);
  }
}

static void start_line(Scanner *s, unsigned col, LineStart start) {
  s->line_col = (uint16_t)col;
  s->content_col = (uint16_t)(start.list_marker ? col + 2 : col);
}

/* At the end of a line: a continuation, an indent, a dedent or a newline. */
static bool scan_line_end(Scanner *s, TSLexer *lexer, const bool *valid) {
  bool blank = false;
  bool eof = lexer->eof(lexer);
  /* at the end of the input with no newline, only the dedents are given:
   * a newline there would be a token of no width, again and again */
  bool consumed = !eof;
  unsigned col = 0;
  if (!eof) {
    advance(lexer); /* the newline */
    for (;;) {
      col = 0;
      while (is_space(lexer->lookahead) || lexer->lookahead == '\r') {
        if (lexer->lookahead != '\r') col++;
        advance(lexer);
      }
      if (lexer->eof(lexer)) {
        eof = true;
        col = 0;
        break;
      }
      if (lexer->lookahead != '\n') break;
      blank = true;
      advance(lexer);
    }
  }
  lexer->mark_end(lexer);
  LineStart start = eof ? (LineStart){false, false} : line_start(lexer);

  if (valid[CONTINUATION] && !blank && !eof &&
      (col > s->content_col || (col == s->content_col && !start.block_start))) {
    lexer->result_symbol = CONTINUATION;
    return true;
  }
  unsigned top = s->stack[s->depth - 1];
  if (valid[INDENT] && !eof && col > top && s->depth < MAX_DEPTH) {
    s->stack[s->depth++] = (uint16_t)col;
    start_line(s, col, start);
    lexer->result_symbol = INDENT;
    return true;
  }
  if (col < top && valid[DEDENT]) {
    unsigned k = 0;
    while (s->depth > 1 && s->stack[s->depth - 1] > col) {
      s->depth--;
      k++;
    }
    s->pending_dedents = (uint8_t)(k - 1);
    s->pending_newline = !eof;
    start_line(s, col, start);
    lexer->result_symbol = DEDENT;
    return true;
  }
  if (valid[NEWLINE] && consumed) {
    start_line(s, col, start);
    lexer->result_symbol = NEWLINE;
    return true;
  }
  return false;
}

/* A comment from %% (or %%=) to %%, which may cross lines but not a blank
 * line. The lexer is after the first %. */
static bool scan_comment(TSLexer *lexer, const bool *valid) {
  advance(lexer); /* the second % */
  bool proof = lexer->lookahead == '=';
  if (proof) advance(lexer);
  if (!valid[proof ? PROOF_COMMENT : COMMENT]) return false;
  for (;;) {
    if (lexer->eof(lexer)) return false;
    if (lexer->lookahead == '%') {
      advance(lexer);
      if (lexer->lookahead == '%') {
        advance(lexer);
        lexer->mark_end(lexer);
        lexer->result_symbol = proof ? PROOF_COMMENT : COMMENT;
        return true;
      }
      continue;
    }
    if (lexer->lookahead == '\n') {
      advance(lexer);
      while (is_space(lexer->lookahead) || lexer->lookahead == '\r') advance(lexer);
      if (lexer->lookahead == '\n' || lexer->eof(lexer)) return false;
      continue;
    }
    advance(lexer);
  }
}

/* Text up to [, \, the end of the line, %% or ##N; in a slot also | and ],
 * in a cell also |. any: the lexer has read text already. */
static bool scan_text(TSLexer *lexer, enum TokenType kind, bool any) {
  if (any) lexer->mark_end(lexer);
  for (;;) {
    int32_t c = lexer->lookahead;
    if (lexer->eof(lexer) || c == '\n' || c == '\r' || c == '[' || c == '\\') break;
    if (kind == SLOT_TEXT && (c == '|' || c == ']')) break;
    if (kind == CELL_TEXT && c == '|') break;
    advance(lexer);
    if (c == '%' && lexer->lookahead == '%') break;
    if (c == '#' && lexer->lookahead == '#') {
      advance(lexer);
      if (is_digit(lexer->lookahead)) break;
    }
    any = true;
    lexer->mark_end(lexer);
  }
  if (!any) return false;
  lexer->result_symbol = kind;
  return true;
}

bool tree_sitter_golem_external_scanner_scan(void *payload, TSLexer *lexer, const bool *valid) {
  Scanner *s = payload;
  /* every symbol is valid only while the parser recovers from an error */
  bool recovering = valid[ERROR_SENTINEL];

  if (s->pending_dedents > 0) {
    s->pending_dedents--;
    if (valid[DEDENT]) {
      lexer->result_symbol = DEDENT;
      return true;
    }
    s->pending_dedents = 0;
  }
  if (s->pending_newline) {
    s->pending_newline = false;
    if (valid[NEWLINE]) {
      lexer->result_symbol = NEWLINE;
      return true;
    }
  }

  if (!recovering && (valid[CODE_CONTENT] || valid[CODE_CLOSE])) {
    while (is_space(lexer->lookahead) || lexer->lookahead == '\r') lexer->advance(lexer, true);
    if (lexer->lookahead == '\n' || lexer->eof(lexer)) return scan_code(s, lexer, valid);
    return false;
  }

  while (is_space(lexer->lookahead) || lexer->lookahead == '\r') lexer->advance(lexer, true);

  if (lexer->lookahead == '\n' || lexer->eof(lexer)) {
    if (valid[NEWLINE] || valid[INDENT] || valid[DEDENT] || valid[CONTINUATION]) {
      return scan_line_end(s, lexer, valid);
    }
    return false;
  }

  if (valid[PARAGRAPH_START] && !recovering) {
    lexer->mark_end(lexer);
    LineStart start = line_start(lexer);
    if (start.block_start) return false;
    lexer->result_symbol = PARAGRAPH_START;
    return true;
  }

  enum TokenType kind = valid[SLOT_TEXT] ? SLOT_TEXT : valid[CELL_TEXT] ? CELL_TEXT : TEXT;
  bool text = valid[kind];

  if (lexer->lookahead == '%') {
    advance(lexer);
    if (lexer->lookahead == '%') return scan_comment(lexer, valid);
    return text && scan_text(lexer, kind, true);
  }
  if (lexer->lookahead == '#') {
    advance(lexer);
    if (lexer->lookahead == '#') {
      advance(lexer);
      if (valid[NUMBER_CLOSE]) {
        lexer->mark_end(lexer);
        lexer->result_symbol = NUMBER_CLOSE;
        return true;
      }
      if (is_digit(lexer->lookahead) && valid[NUMBER_OPEN]) {
        lexer->mark_end(lexer);
        lexer->result_symbol = NUMBER_OPEN;
        return true;
      }
    }
    return text && scan_text(lexer, kind, true);
  }
  return text && scan_text(lexer, kind, false);
}
