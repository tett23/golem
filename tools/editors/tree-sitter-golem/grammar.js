/**
 * The tree-sitter grammar of .gm, the markup of Golem
 * (docs/adr/0170-emet-editor-support.md, docs/markup.md).
 *
 * It is written apart from the grammar that Golem parses with
 * (modules/golem-parser/grammar/Golem.hpeg) and accepts what that grammar
 * accepts; where the two differ, this one is the more lenient and keeps
 * fewer distinctions (see tools/editors/README.md).
 *
 * What depends on the context is read by the external scanner
 * (src/scanner.c):
 *
 * - the lines: a newline between two blocks of the same indentation, a
 *   deeper line that starts the body of a block command, of a list item or
 *   of a term (indent), a shallower one that ends it (dedent), and a line
 *   that continues the paragraph, the list item or the prose slot before it
 *   (continuation: no blank line between, and the indentation of the text
 *   of that block, or more, without a character that starts a block);
 * - the start of a paragraph: a line that does not start a block;
 * - the text, which stops at [, \, the end of the line, %% and ##N (and at
 *   | and ] in a prose slot, at | in a cell of a table);
 * - comments, which may cross lines but not a blank line;
 * - the ## of the number shorthand, and the lines of a code block, which
 *   end at the fence of the same indentation.
 *
 * Both separators of paragraphs (the blank line and the line, docs/adr/0013)
 * give the same tree: a paragraph node holds the lines that the scanner
 * joins, and the separator only changes what Golem makes of them.
 */

// item (newline item?)*: blocks separated by newlines; the scanner reads
// the blank lines into the newline
function blocks($) {
  return seq($._block, repeat(seq($._newline, optional($._block))));
}

function sep1(item, separator) {
  return seq(item, repeat(seq(separator, item)));
}

const PREC = {
  range: 1,
  compare: 2,
  add: 3,
  mul: 4,
  unary: 5,
  pow: 6,
};

module.exports = grammar({
  name: 'golem',

  externals: $ => [
    $._newline,
    $._indent,
    $._dedent,
    $._continuation,
    $._paragraph_start,
    $._text,
    $._slot_text,
    $._cell_text,
    $.comment,
    $.proof_comment,
    $._number_open,
    $._number_close,
    $.code_content,
    $._code_close,
    $._error_sentinel,
  ],

  extras: _ => [/[ \t]/],

  // A newline after a list item, a term or a row of a table may go on the
  // list or start the next block; the parser keeps both until the next
  // line tells, and prefers fewer lists (prec.dynamic) when both fit.
  conflicts: $ => [
    [$.bullet_list],
    [$.ordered_list],
    [$.definition_list],
    [$.table],
  ],

  rules: {
    document: $ => seq(optional($._newline), optional(blocks($))),

    _block: $ => choice(
      $.heading,
      $.paragraph,
      $.bullet_list,
      $.ordered_list,
      $.definition_list,
      $.table,
      $.code_block,
      $.block_command,
      $.set_command,
    ),

    // the body of a block command, a list item or a term: the deeper lines
    body: $ => seq($._indent, blocks($), $._dedent),

    // ---------------------------------------------------------- headings

    heading: $ => seq(
      // # to ###### (docs/adr/0188); the scanner does not start a block at seven or more
      field('marker', alias(choice('#', '##', '###', '####', '#####', '######'), $.heading_marker)),
      repeat1($._head_inline),
    ),

    // ---------------------------------------------------------- paragraphs

    paragraph: $ => seq($._paragraph_start, repeat1($._inline)),

    _inline: $ => choice($._head_inline, $.hard_break, $._continuation),

    // the inlines of a line that cannot go on: headings and terms
    _head_inline: $ => choice(
      $.escape,
      $.proof_comment,
      $.comment,
      $.expression,
      $.inline_command,
      $.number_shorthand,
      alias($._text, $.text),
    ),

    escape: _ => token(seq('\\', /[^\n]/)),

    // a backslash at the end of a line, and the line that goes on
    hard_break: $ => seq('\\', $._continuation),

    // ##12##
    number_shorthand: $ => seq(
      alias($._number_open, $.number_mark),
      alias(/[^#\n\[\]|\\]+/, $.number_body),
      optional(alias($._number_close, $.number_mark)),
    ),

    // ---------------------------------------------------------- commands

    inline_command: $ => seq(
      '[',
      field('name', $.command_name),
      repeat($._argument),
      optional($.prose_slots),
      ']',
    ),

    command_name: _ => token.immediate(/[a-z][a-z0-9\-]*(\.[a-z][a-z0-9\-]*)?/),

    _argument: $ => choice($.argument, $.keyword_argument, $.splat_argument),

    argument: $ => $._argument_value,

    keyword_argument: $ => seq(
      field('name', alias($._word, $.argument_name)),
      token.immediate('='),
      field('value', $._argument_value),
    ),

    _argument_value: $ => choice(
      alias($._string, $.string),
      $.expression,
      $.inline_command,
      alias($._word, $.word),
    ),

    // *[xs], **[h]
    splat_argument: $ => seq(choice('*[', '**['), $._expr, ']'),

    _word: _ => /[^ \t\n\]:|=\["\\]+/,

    _string: _ => /"(\\.|[^"\\\n])*"/,

    prose_slots: $ => seq(
      ':',
      optional($.prose_slot),
      repeat(seq('|', optional($.prose_slot))),
    ),

    prose_slot: $ => repeat1(choice(
      $.escape,
      $.hard_break,
      $.proof_comment,
      $.comment,
      $.expression,
      $.inline_command,
      $.number_shorthand,
      alias($._slot_text, $.text),
      $._continuation,
    )),

    // ---------------------------------------------------------- expressions

    expression: $ => seq('[=', $._expr, ']'),

    _expr: $ => choice(
      $.range_expression,
      $.binary_expression,
      $.unary_expression,
      $.call_expression,
      $.variable_expression,
      $.number,
      alias($._string, $.string),
      $.keyword,
      $.array,
      $.hash,
      $.parenthesized_expression,
    ),

    range_expression: $ => prec.left(PREC.range, seq($._expr, '...', $._expr)),

    binary_expression: $ => choice(
      ...['==', '!=', '<=', '>=', '<', '>'].map(op =>
        prec.left(PREC.compare, seq(field('left', $._expr), field('operator', op), field('right', $._expr)))),
      ...['+', '-'].map(op =>
        prec.left(PREC.add, seq(field('left', $._expr), field('operator', op), field('right', $._expr)))),
      ...['*', '/', '%'].map(op =>
        prec.left(PREC.mul, seq(field('left', $._expr), field('operator', op), field('right', $._expr)))),
      prec.right(PREC.pow, seq(field('left', $._expr), field('operator', '**'), field('right', $._expr))),
    ),

    unary_expression: $ => prec(PREC.unary, seq(field('operator', '-'), field('operand', $._expr))),

    // f(x), book.total(xs)
    call_expression: $ => seq(
      field('function', alias($._identifier, $.function)),
      optional(seq(token.immediate('.'), field('function', alias($._immediate_identifier, $.function)))),
      token.immediate('('),
      optional(sep1($._expr, ',')),
      ')',
    ),

    // x, chapter.title
    variable_expression: $ => seq(
      alias($._identifier, $.variable),
      repeat(seq(token.immediate('.'), alias($._immediate_identifier, $.variable))),
    ),

    _identifier: _ => /[a-zA-Z_][a-zA-Z0-9_]*/,

    _immediate_identifier: _ => token.immediate(/[a-zA-Z_][a-zA-Z0-9_]*/),

    number: _ => /[0-9]+(\.[0-9]+)?(e[+\-]?[0-9]+)?/,

    keyword: _ => choice('true', 'false', 'nil'),

    array: $ => seq('[', optional(sep1($._expr, ',')), ']'),

    hash: $ => seq('{', optional(sep1($.hash_entry, ',')), '}'),

    hash_entry: $ => seq(
      field('key', choice(alias($._identifier, $.key), alias($._string, $.string))),
      ':',
      field('value', $._expr),
    ),

    parenthesized_expression: $ => seq('(', $._expr, ')'),

    // ---------------------------------------------------------- block commands

    block_command: $ => seq(
      '@',
      field('name', $.command_name),
      repeat($._argument),
      optional($.body),
    ),

    // @set name = expression
    set_command: $ => seq(
      '@',
      token.immediate('set'),
      field('name', alias($._identifier, $.set_name)),
      '=',
      field('value', $._expr),
    ),

    // ---------------------------------------------------------- lists

    bullet_list: $ => prec.dynamic(-1, sep1($.bullet_item, $._newline)),

    bullet_item: $ => seq(
      alias('-', $.list_marker),
      repeat1($._inline),
      optional($.body),
    ),

    ordered_list: $ => prec.dynamic(-1, sep1($.ordered_item, $._newline)),

    ordered_item: $ => seq(
      alias('+', $.list_marker),
      repeat1($._inline),
      optional($.body),
    ),

    // = term (one or more), the body of the last; =: and another body
    definition_list: $ => prec.dynamic(-1, sep1(choice($.term, $.new_definition), $._newline)),

    term: $ => seq(alias('=', $.term_marker), repeat1($._head_inline), optional($.body)),

    new_definition: $ => seq(alias('=:', $.term_marker), $.body),

    // ---------------------------------------------------------- tables

    table: $ => seq(
      $.table_row,
      $._newline,
      $.table_delimiter_row,
      repeat(seq($._newline, $.table_row)),
    ),

    table_row: $ => seq('|', repeat1(seq(optional($.table_cell), '|'))),

    table_cell: $ => repeat1(choice(
      $.escape,
      $.comment,
      $.expression,
      $.inline_command,
      $.number_shorthand,
      alias($._cell_text, $.text),
    )),

    table_delimiter_row: $ => seq('|', repeat1(seq(alias(/:?-+:?/, $.table_delimiter), '|'))),

    // ---------------------------------------------------------- code blocks

    code_block: $ => seq(
      alias('```', $.fence),
      optional(field('language', alias(token.immediate(/[a-zA-Z0-9_+\-]+/), $.language))),
      repeat($._argument),
      optional($.code_content),
      $._code_close,
      alias('```', $.fence),
    ),
  },
});
