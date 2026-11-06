; The highlights of .emet (docs/adr/0170-emet-editor-support.md): the
; classes of the semantic tokens of .emet, by the captures of
; nvim-treesitter. Every node matches one pattern only, so the result does
; not depend on whether an editor lets the first or the last pattern win.

(comment) @comment

[
  "pub"
  "inline"
  "block"
  "filter"
  "fn"
  "data"
  "type"
  "import"
  "where"
  "case"
  "of"
] @keyword

(otherwise) @keyword

; the names of signatures and equations, and of the bindings of where
(function_name) @function

; the head of an application: f in f x, map in List.map xs
(function) @function

(variable) @variable

(field_name) @variable

(parameter) @variable.parameter

(type) @type

(constructor_name) @type

(type_variable) @type

(row_variable) @type

(constructor) @constructor

(module) @module

(string) @string

(char) @string

(number) @number

(binary_expression
  operator: _ @operator)

(negation
  "-" @operator)

(negative_number
  "-" @operator)

(ternary_expression
  [
    "?"
    ":"
  ] @operator)

(cons_pattern
  ":" @operator)

[
  "="
  "->"
  "::"
] @operator

(guard
  "|" @operator)

(guard_alternative
  "|" @operator)

(data
  "|" @operator)

; the row of requirements: <file "a.tsv" | e>
(row
  [
    "<"
    ">"
    "|"
  ] @keyword.modifier)

(requirement_kind) @keyword.modifier
