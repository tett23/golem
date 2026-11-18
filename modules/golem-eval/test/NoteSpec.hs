-- | Notes of more than one paragraph: [note name] and @note name (docs/adr/0263).
module NoteSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Parser.SourceSettings (ParagraphSeparator (..), SourceSettings (..))
import Golem.Project.Style (defaultStyle, paraLineBreaks)
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

ctx :: EvalContext
ctx = baseCtx {ctxParaStyles = paraLineBreaks defaultStyle}

lineCtx :: EvalContext
lineCtx = ctx {ctxSource = SourceSettings LineSeparated}

-- | The bodies of the notes of a source, each paragraph its text and its style, with the codes of the diagnostics.
notesOf :: EvalContext -> Text -> ([[(Maybe Text, Text)]], [Text])
notesOf c src =
  let (ds, r) = evalSource c src
   in ([map para body | b <- resultBodies r, Note _ _ body <- inlinesOf b], map diagCodeText ds)
  where
    para = \case
      Block _ _ _ (Paragraph st is) -> (st, T.concat [t | Text _ t <- is])
      _ -> (Just "?", "")
    inlinesOf = \case
      Paragraph _ is -> deep is
      BulletList items -> concat [deep is | ListItem _ bs <- items, Block _ _ _ (Paragraph _ is) <- bs]
      _ -> []
    deep = concatMap (\i -> i : case i of CharStyle _ _ xs -> deep xs; _ -> [])

-- | The codes of the diagnostics of a source.
codesOf :: EvalContext -> Text -> [Text]
codesOf c = snd . notesOf c

tests :: TestTree
tests =
  testGroup
    "notes of more than one paragraph (docs/adr/0263)"
    [ testCase "I1: [note: body] is a note of one paragraph without a style, its inlines the body" $
        notesOf ctx "本文[note: 注の本文]。\n" @?= ([[(Nothing, "注の本文")]], []),
      testCase "I1: a sidenote is a body of one paragraph" $ do
        let (ds, r) = evalSource ctx "本文[sidenote: 傍注]。\n"
        map diagCodeText ds @?= []
        [length body | Paragraph _ is <- resultBodies r, Sidenote _ _ body <- is] @?= [1],
      testCase "the blank-line style: a paragraph for each run of lines between blank lines" $
        notesOf ctx "本文[note k]。\n\n@note k\n  一つめの\n  段落。\n\n  二つめ。\n" @?= ([[(Nothing, "一つめの段落。"), (Nothing, "二つめ。")]], []),
      testCase "the line style: a paragraph for each line" $
        notesOf lineCtx "本文[note k]。\n@note k\n  一つめ。\n  二つめ。\n  三つめ。\n" @?= ([[(Nothing, "一つめ。"), (Nothing, "二つめ。"), (Nothing, "三つめ。")]], []),
      testCase "I3: [note name] takes the body of @note name before or after it, and in a list item" $ do
        notesOf ctx "@note k\n  前。\n\n本文[note k]。\n" @?= ([[(Nothing, "前。")]], [])
        notesOf ctx "- 項目[note k]。\n\n@note k\n  後。\n" @?= ([[(Nothing, "後。")]], [])
        notesOf ctx "- 項目[note k]。\n\n  @note k\n    中。\n" @?= ([[(Nothing, "中。")]], []),
      testCase "the names of notes are apart from the labels" $
        codesOf ctx "@label k\n本文[note k]。\n\n@note k\n  注。\n" @?= [],
      testCase "the body reads the values of @set up to @note" $
        notesOf ctx "@set x = \"一\"\n\n本文[note k]。\n\n@note k\n  [= x]。\n" @?= ([[(Nothing, "一。")]], []),
      testCase "the boundaries of the numbers of [note name] and @note: 0 and 1, 1 and 0, 1 and 1, 2 and 1, 1 and 2" $ do
        codesOf ctx "@note k\n  注。\n" @?= ["G02138"]
        notesOf ctx "本文[note k]。\n" @?= ([], ["G02137"])
        codesOf ctx "本文[note k]。\n\n@note k\n  注。\n" @?= []
        notesOf ctx "本文[note k]と[note k]。\n\n@note k\n  注。\n" @?= ([[(Nothing, "注。")]], ["G02139"])
        notesOf ctx "本文[note k]。\n\n@note k\n  一。\n\n@note k\n  二。\n" @?= ([[(Nothing, "一。")]], ["G02140"]),
      testCase "G02142: [note] and @note without one word of a name" $ do
        codesOf ctx "本文[note]。\n" @?= ["G02142"]
        codesOf ctx "本文[note a b]。\n" @?= ["G02142"]
        codesOf ctx "本文[note [= 1]]。\n" @?= ["G02142"]
        codesOf ctx "@note\n  注。\n" @?= ["G02142"]
        codesOf ctx "@note a b\n  注。\n" @?= ["G02142"],
      testCase "G02038: a name and a prose slot together" $ do
        let (ds, _) = evalSource ctx "本文[note k: 注]。\n\n@note k\n  注。\n"
        [(diagCodeText d, diagMessage d) | d <- ds] @?= [("G02038", "note は名前を書くと散文スロットを取りません"), ("G02138", "使われない注の本文です: k")],
      testCase "G02141 at each block of the body that is not a paragraph, which is dropped" $ do
        notesOf ctx "本文[note k]。\n\n@note k\n  一。\n\n  - 項目\n\n  二。\n" @?= ([[(Nothing, "一。"), (Nothing, "二。")]], ["G02141"])
        notesOf ctx "本文[note k]。\n\n@note k\n  一。\n\n  @note j\n    中。\n" @?= ([[(Nothing, "一。")]], ["G02141"]),
      testCase "G02143 for no body; not when G02141 leaves no paragraph; [note] of such a body puts out nothing" $ do
        notesOf ctx "本文[note k]。\n\n@note k\n" @?= ([], ["G02143"])
        notesOf ctx "本文[note k]。\n\n@note k\n  - 項目\n" @?= ([], ["G02141"]),
      testCase "G02013: attributes on @note, and @style on a paragraph of its body, whose style is dropped" $ do
        codesOf ctx "本文[note k]。\n\n@label x\n@note k\n  注。\n" @?= ["G02013"]
        notesOf ctx "本文[note k]。\n\n@note k\n  @style verse\n  注。\n" @?= ([[(Nothing, "注。")]], ["G02013"])
        -- @lang on a paragraph of the body is fine
        codesOf ctx "本文[note k]。\n\n@note k\n  @lang en\n  Note.\n" @?= [],
      testCase "I8: the diagnostics of notes keep their order" $ do
        let src = "[note a][note b][note b]\n\n@note b\n  一。\n\n@note b\n  二。\n\n@note c\n  三。\n"
        codesOf ctx src @?= codesOf ctx src
        codesOf ctx src @?= ["G02140", "G02137", "G02139", "G02138"]
    ]
