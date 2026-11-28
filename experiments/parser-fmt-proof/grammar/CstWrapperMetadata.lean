import Generated
namespace CstWrapper
theorem word_token : Generated.pegGrammar.tokens.contains "Word" = true := by decide
theorem word_not_inline : Generated.pegGrammar.inline.contains "Word" = false := by decide
theorem string_token : Generated.pegGrammar.tokens.contains "StringLit" = true := by decide
theorem string_not_inline : Generated.pegGrammar.inline.contains "StringLit" = false := by decide
theorem eq_token : Generated.pegGrammar.tokens.contains "Eq" = true := by decide
theorem eq_not_inline : Generated.pegGrammar.inline.contains "Eq" = false := by decide
theorem argvalue_inline : Generated.pegGrammar.inline.contains "ArgValue" = true := by decide
theorem keyword_not_inline : Generated.pegGrammar.inline.contains "KeywordArgument" = false := by decide
theorem keyword_not_token : Generated.pegGrammar.tokens.contains "KeywordArgument" = false := by decide

end CstWrapper
