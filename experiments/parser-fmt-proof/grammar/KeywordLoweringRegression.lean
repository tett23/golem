import KeywordLowering
open KeywordLowering
#eval show IO Unit from do
  let input : List Token := [⟨.whitespace," ".toList⟩,⟨.word,"mode".toList⟩,
    ⟨.whitespace," ".toList⟩,⟨.equals,"=".toList⟩,⟨.whitespace," ".toList⟩,
    ⟨.word,"plain".toList⟩,⟨.whitespace," ".toList⟩]
  let got := lowerKeyword input
  unless got == some ("mode".toList,QuotedKeywords.Value.word "plain".toList) do
    throw (IO.userError s!"CST keyword fields mismatch: {repr got}")
  IO.println "CST keyword fields matched"
