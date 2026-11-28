import MixedKeywords
#eval show IO Unit from do
  let got := MixedKeywords.parseArgs 2 " mode=plain text=\"quoted\"\n".toList
  let expected := some [("mode".toList,QuotedKeywords.Value.word "plain".toList),
    ("text".toList,QuotedKeywords.Value.string "quoted".toList)]
  unless got == expected do throw (IO.userError s!"mixed fields mismatch: {repr got}")
