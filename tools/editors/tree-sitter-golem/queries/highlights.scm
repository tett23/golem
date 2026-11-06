; The highlights of .gm (docs/adr/0170-emet-editor-support.md): the classes
; of the semantic tokens of golem-lsp ADR 0006, by the captures of
; nvim-treesitter. Every node matches one pattern only, so the result does
; not depend on whether an editor lets the first or the last pattern win.
; Text, the text of prose slots and the lines of code blocks have no
; capture, as they have no semantic token.

(comment) @comment

(proof_comment) @comment

; @label intro, @set
(block_command
  "@" @attribute
  name: (command_name) @attribute)

(set_command
  [
    "@"
    "set"
  ] @attribute)

; [ruby 漢字: かんじ]
(inline_command
  name: (command_name) @function)

(argument_name) @variable.parameter

(word) @string

(string) @string

; [= ... ]
"[=" @keyword

(number) @number

(keyword) @keyword

(variable) @variable

(function) @function

(binary_expression
  operator: _ @operator)

(unary_expression
  operator: _ @operator)

(range_expression
  "..." @operator)

(escape) @string.escape

(number_mark) @operator

(number_body) @number

(heading_marker) @keyword

(heading
  (text) @module)

(list_marker) @keyword

(term
  (term_marker) @keyword)

(table_row
  "|" @operator)

(table_delimiter_row
  "|" @operator)

(table_delimiter) @operator

(prose_slots
  "|" @operator)

(fence) @keyword

(language) @type
