{- | The reading stage of a source, shared by golem-parser and golem-emet
(docs/adr/0173): the same diagnostics, codes, spans and messages, as
golem-parser's 'readSource' and golem-emet's 'readEmet' gave before.
-}
module ReadSpec (tests) where

import Data.ByteString (ByteString)
import Data.Text.Encoding (encodeUtf8)
import Golem.Syntax
import Golem.Syntax.Read
import Test.Tasty
import Test.Tasty.HUnit

fid :: FileId
fid = FileId 0

bom, invalid, cr :: Int -> Diagnostic
bom _ = diagnostic "G01002" Error (mkSpan fid 0 3) "ファイルの先頭に BOM があります。BOM を取り除いてください"
invalid i = diagnostic "G01001" Error (mkSpan fid i (i + 1)) "UTF-8 として不正なバイト列があります"
cr i = (diagnostic "G01003" Error (mkSpan fid i (i + 1)) "改行に CR が含まれています。改行は LF に限ります") {diagFixes = [Fix "golem fmt で LF に直す" []]}

readsAs :: ByteString -> Either [Diagnostic] () -> Assertion
readsAs bs expected = (() <$ readSourceBytes fid bs) @?= expected

tests :: TestTree
tests =
  testGroup
    "read"
    [ testCase "a BOM at the start is G01002" $
        readsAs "\xEF\xBB\xBFtext\n" (Left [bom 0]),
      testCase "a BOM before invalid UTF-8 is G01002 only" $
        readsAs "\xEF\xBB\xBF\xFF\r\n" (Left [bom 0]),
      testCase "invalid UTF-8 in the middle is G01001 at its first byte" $
        readsAs "ab\xFF\ncd\n" (Left [invalid 2]),
      testCase "a multibyte character cut at the end is G01001 at its first byte" $
        readsAs "a\xE3\x81" (Left [invalid 1]),
      testCase "invalid UTF-8 after a valid multibyte character" $
        readsAs "\xE3\x81\x82\xC0\x80" (Left [invalid 3]),
      testCase "a lone CR is G01003 at the CR" $
        readsAs "a\rb\n" (Left [cr 1]),
      testCase "CRLF is G01003 at the first CR" $
        readsAs "\xE3\x81\x82\r\nb\r\n" (Left [cr 3]),
      testCase "a text without them reads" $
        readSourceBytes fid (encodeUtf8 "あい\nう\n") @?= Right "あい\nう\n",
      testCase "the check of a decoded text: a BOM, then a CR" $ do
        checkSourceText fid "\xFEFF\&a\r" @?= [bom 0]
        checkSourceText fid "a\r\n" @?= [cr 1]
        checkSourceText fid "a\n" @?= [],
      testCase "invalidOffset is the length of valid UTF-8" $
        invalidOffset "abc" @?= 3
    ]
