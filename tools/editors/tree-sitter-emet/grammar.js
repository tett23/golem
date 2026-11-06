/**
 * The tree-sitter grammar of .emet, the language of functions of Golem
 * (docs/adr/0170-emet-editor-support.md).
 *
 * It is written apart from the grammar that Golem parses with
 * (modules/golem-emet/grammar/Emet.hpeg) and accepts what that grammar
 * accepts; where the two differ, this one is the more lenient (see
 * tools/editors/README.md).
 *
 * Newlines: there is no offside rule. A newline separates the top-level
 * declarations, the bindings of where { } and the alternatives of
 * case ... of { }, except where the tokens show that the line goes on. The
 * external scanner (src/scanner.c) makes that choice: it gives the
 * separator token only where the parser can take one (so never inside
 * ( ), [ ] and the { } of a record, nor after an operator, =, ->, ::, ',',
 * ? or :), and only when the next line does not start with |, a binary
 * operator but -, ?, :, where or ->. Every other newline is white space.
 *
 * The true branch of c ? a : b has no : at its top, as in Emet.hpeg
 * (TrueBranch): the binary expressions are written twice, once without
 * the : of lists.
 */

const PREC = {
  ternary: 1,
  or: 2,
  and: 3,
  cmp: 4,
  append: 5,
  add: 6,
  mul: 7,
  neg: 8,
  pow: 9,
  app: 10,
};

// [operator, precedence, associativity]
const OPERATORS = [
  ['||', PREC.or, 'right'],
  ['&&', PREC.and, 'right'],
  ['==', PREC.cmp, 'left'],
  ['/=', PREC.cmp, 'left'],
  ['<=', PREC.cmp, 'left'],
  ['>=', PREC.cmp, 'left'],
  ['<', PREC.cmp, 'left'],
  ['>', PREC.cmp, 'left'],
  ['++', PREC.append, 'right'],
  [':', PREC.append, 'right'],
  ['+', PREC.add, 'left'],
  ['-', PREC.add, 'left'],
  ['*', PREC.mul, 'left'],
  ['/', PREC.mul, 'left'],
  ['%', PREC.mul, 'left'],
  ['**', PREC.pow, 'right'],
];

const ESCAPE = /\\(["'\\nt]|u\{[0-9A-Fa-f]+\})/;

// item (sep item?)* with an optional first item: the separators of
// Items<p> in Emet.hpeg, where blank lines are separators too
function items($, item) {
  return seq(optional(item), repeat(seq($._separator, optional(item))));
}

function commaSep(item) {
  return optional(seq(item, repeat(seq(',', item))));
}

function binary($, operand, withCons) {
  return choice(
    ...OPERATORS.filter(([op]) => withCons || op !== ':').map(([op, p, assoc]) =>
      (assoc === 'right' ? prec.right : prec.left)(
        p,
        seq(field('left', operand), field('operator', op), field('right', operand)),
      ),
    ),
  );
}

// The rules of the patterns, their names ending in suffix; binder is the
// node of a variable. The rules with a suffix are aliased to those without.
function patterns(suffix, binder) {
  const r = name => $ => (suffix ? alias($[name + suffix], $[name]) : $[name]);
  const n = name => $ => $[name + suffix];
  return {
    ['_pattern' + suffix]: $ => choice(r('cons_pattern')($), r('constructor_pattern')($), n('_apattern')($)),
    ['cons_pattern' + suffix]: $ => prec.right(seq(
      field('head', choice(r('constructor_pattern')($), n('_apattern')($))),
      ':',
      field('tail', n('_pattern')($)),
    )),
    ['constructor_pattern' + suffix]: $ => seq(
      field('constructor', $._constructor_ref),
      repeat1(field('argument', n('_apattern')($))),
    ),
    ['_apattern' + suffix]: $ => choice(
      $.wildcard,
      binder($),
      $.number,
      $.negative_number,
      $.string,
      $.char,
      r('list_pattern')($),
      r('record_pattern')($),
      $._constructor_ref,
      r('tuple_pattern')($),
      r('parenthesized_pattern')($),
    ),
    ['list_pattern' + suffix]: $ => seq('[', commaSep(n('_pattern')($)), ']'),
    ['record_pattern' + suffix]: $ => seq(
      field('constructor', $._constructor_ref),
      '{',
      commaSep(r('field_pattern')($)),
      '}',
    ),
    ['field_pattern' + suffix]: $ => seq(field('name', $._field_name), '=', field('pattern', n('_pattern')($))),
    ['tuple_pattern' + suffix]: $ => seq('(', n('_pattern')($), repeat1(seq(',', n('_pattern')($))), ')'),
    ['parenthesized_pattern' + suffix]: $ => seq('(', n('_pattern')($), ')'),
  };
}

module.exports = grammar({
  name: 'emet',

  word: $ => $.variable,

  externals: $ => [$._separator],

  extras: $ => [/[ \t\r\n]/, $.comment],

  supertypes: $ => [$._expression, $._pattern, $._type],

  rules: {
    source_file: $ => items($, $._declaration),

    _declaration: $ => choice(
      $.import,
      $.data,
      $.type_alias,
      $.signature,
      $.equation,
    ),

    comment: _ => token(seq('--', /[^\n]*/)),

    // ---------------------------------------------------------- declarations

    import: $ => seq('import', field('path', $.string)),

    data: $ => seq(
      optional('pub'),
      'data',
      field('name', $.type),
      repeat(field('parameter', $._type_variable)),
      '=',
      $.constructor_declaration,
      repeat(seq('|', $.constructor_declaration)),
    ),

    // the names of a data declaration are types (docs/adr/0170)
    constructor_declaration: $ => choice(
      seq(field('name', alias($._upper, $.constructor_name)), repeat($._atype)),
      seq(
        field('name', alias($._upper, $.constructor_name)),
        '{',
        commaSep($.field_declaration),
        '}',
      ),
    ),

    field_declaration: $ => seq(field('name', $._field_name), '::', field('type', $._type)),

    type_alias: $ => seq(
      optional('pub'),
      'type',
      field('name', $.type),
      repeat(field('parameter', $._type_variable)),
      '=',
      field('type', $._type),
    ),

    // pub, maybe with the kind of a function .gm uses and the name it uses
    // there (docs/adr/0162): pub inline "tax-included"
    signature: $ => seq(
      optional($.export),
      field('name', $._function_name),
      '::',
      optional(field('row', $.row)),
      field('type', $._type),
    ),

    export: $ => seq(
      'pub',
      optional(seq(
        field('kind', choice('inline', 'block', 'filter', 'fn')),
        optional(field('name', $.string)),
      )),
    ),

    equation: $ => seq(
      field('name', $._function_name),
      repeat(field('pattern', $._apattern)),
      choice(
        seq('=', field('body', $._expression), repeat($.where)),
        repeat1($.guard),
      ),
    ),

    guard: $ => seq(
      '|',
      field('condition', choice($.otherwise, $._expression)),
      '=',
      field('body', $._expression),
      repeat($.where),
    ),

    otherwise: _ => 'otherwise',

    where: $ => seq(
      'where',
      '{',
      items($, choice($.signature_local, $.equation)),
      '}',
    ),

    signature_local: $ => seq(
      field('name', $._function_name),
      '::',
      optional(field('row', $.row)),
      field('type', $._type),
    ),

    // ---------------------------------------------------------- types

    _type: $ => choice($.function_type, $._btype),

    function_type: $ => prec.right(seq(
      field('parameter', $._btype),
      '->',
      optional(field('row', choice($.row, $._row_variable))),
      field('result', $._type),
    )),

    // a row of requirements (docs/adr/0161): <file "a.tsv" | e>
    row: $ => seq(
      '<',
      commaSep($.requirement),
      optional(seq('|', $._row_variable)),
      '>',
    ),

    requirement: $ => seq(field('kind', alias($.variable, $.requirement_kind)), repeat(field('argument', $.string))),

    _row_variable: $ => alias($.variable, $.row_variable),

    _btype: $ => choice($.type_application, $._atype),

    type_application: $ => seq(field('constructor', $._type_name), repeat1(field('argument', $._atype))),

    _atype: $ => choice(
      $.keyword_parameter,
      $._type_name,
      $._type_variable,
      $.tuple_type,
      $.parenthesized_type,
    ),

    _type_name: $ => choice($.type, $.qualified_type),

    type: $ => $._upper,

    qualified_type: $ => seq(
      field('module', alias($._upper, $.module)),
      token.immediate('.'),
      field('name', alias($._immediate_upper, $.type)),
    ),

    _type_variable: $ => alias($.variable, $.type_variable),

    // (tax :: Bool = True), ("font-size" :: Rat = 10)
    keyword_parameter: $ => seq(
      '(',
      field('name', choice(alias($.variable, $.parameter), alias($.string, $.parameter))),
      '::',
      field('type', $._type),
      optional(seq('=', field('default', $._expression))),
      ')',
    ),

    parenthesized_type: $ => seq('(', $._type, ')'),

    tuple_type: $ => seq('(', $._type, repeat1(seq(',', $._type)), ')'),

    // ---------------------------------------------------------- patterns
    //
    // Twice: the patterns of the arguments of an equation, whose variables
    // are parameters, and those of the alternatives of case, whose
    // variables are variables (the semantic tokens of docs/adr/0170).

    ...patterns('', $ => alias($.variable, $.parameter)),
    ...patterns('_in_case', $ => $.variable),

    // ---------------------------------------------------------- expressions

    _expression: $ => choice(
      $.case_expression,
      $.ternary_expression,
      $.binary_expression,
      $.negation,
      $._application_or_atom,
    ),

    // the true branch: no ternary and no : of lists at its top
    _true_branch: $ => choice(
      $.case_expression,
      alias($._binary_without_cons, $.binary_expression),
      $.negation,
      $._application_or_atom,
    ),

    case_expression: $ => seq(
      'case',
      field('scrutinee', $._expression),
      'of',
      '{',
      items($, $.alternative),
      '}',
    ),

    alternative: $ => seq(
      field('pattern', $._pattern_in_case),
      choice(
        seq('->', field('body', $._expression), repeat($.where)),
        repeat1($.guard_alternative),
      ),
    ),

    guard_alternative: $ => seq(
      '|',
      field('condition', choice($.otherwise, $._expression)),
      '->',
      field('body', $._expression),
      repeat($.where),
    ),

    ternary_expression: $ => prec.right(PREC.ternary, seq(
      field('condition', $._expression),
      '?',
      field('consequence', $._true_branch),
      ':',
      field('alternative', $._expression),
    )),

    binary_expression: $ => binary($, $._expression, true),

    _binary_without_cons: $ => binary($, $._true_branch, false),

    negation: $ => prec(PREC.neg, seq('-', field('operand', $._expression))),

    _application_or_atom: $ => choice($.application, $._atom),

    application: $ => prec.left(PREC.app, seq(
      field('function', choice($.application, $._head)),
      field('argument', $._atom),
    )),

    // the head of an application: a variable there is a function
    _head: $ => choice(
      alias($.variable, $.function),
      alias($._qualified_function, $.qualified_variable),
      $.parenthesized_expression,
      $.tuple,
      $.list,
      $.number,
      $.string,
      $.char,
      $.record,
      $._constructor_ref,
    ),

    _atom: $ => choice(
      $.parenthesized_expression,
      $.tuple,
      $.list,
      $.number,
      $.string,
      $.char,
      $.qualified_variable,
      $.variable,
      $.record,
      $._constructor_ref,
    ),

    parenthesized_expression: $ => seq('(', $._expression, ')'),

    tuple: $ => seq('(', $._expression, repeat1(seq(',', $._expression)), ')'),

    list: $ => seq('[', commaSep($._expression), ']'),

    record: $ => seq(
      field('constructor', $._constructor_ref),
      '{',
      commaSep($.field_assignment),
      '}',
    ),

    field_assignment: $ => seq(field('name', $._field_name), '=', field('value', $._expression)),

    _field_name: $ => alias($.variable, $.field_name),

    _function_name: $ => alias($.variable, $.function_name),

    wildcard: _ => '_',

    negative_number: $ => seq('-', $.number),

    // ---------------------------------------------------------- names

    _constructor_ref: $ => choice($.constructor, $.qualified_constructor),

    constructor: $ => $._upper,

    qualified_constructor: $ => seq(
      field('module', alias($._upper, $.module)),
      token.immediate('.'),
      field('name', alias($._immediate_upper, $.constructor)),
    ),

    // List.map, String.fromNat
    qualified_variable: $ => seq(
      field('module', alias($._upper, $.module)),
      token.immediate('.'),
      field('name', alias($._immediate_lower, $.variable)),
    ),

    _qualified_function: $ => seq(
      field('module', alias($._upper, $.module)),
      token.immediate('.'),
      field('name', alias($._immediate_lower, $.function)),
    ),

    variable: _ => /[a-z_][A-Za-z0-9_]*/,

    _upper: _ => /[A-Z][A-Za-z0-9_]*/,

    _immediate_upper: _ => token.immediate(/[A-Z][A-Za-z0-9_]*/),

    _immediate_lower: _ => token.immediate(/[a-z_][A-Za-z0-9_]*/),

    // ---------------------------------------------------------- literals

    number: _ => /[0-9]+(\.[0-9]+)?(e[+-]?[0-9]+)?/,

    string: _ => token(seq('"', repeat(choice(/[^"\\\n]/, ESCAPE)), '"')),

    char: _ => token(seq('\'', choice(/[^'\\\n]/, ESCAPE), '\'')),
  },
});
