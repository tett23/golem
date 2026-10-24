-- | The constants and helpers that the tests of golem-layout share.
module Fixtures
  ( fs,
    look0,
    sp,
    sp0,
    compose,
  )
where

import Data.Text (Text)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look)
import Golem.Syntax (FileId (..), SrcSpan, mkSpan)

-- | The font size of 'defaultComposeEnv' in the tests: 10pt.
fs :: Sp
fs = 10 * 65536

-- | The original look of 'defaultComposeEnv'.
look0 :: Look
look0 = ceLook (defaultComposeEnv fs)

-- | The empty span at the start of file 0.
sp :: SrcSpan
sp = mkSpan (FileId 0) 0 0

-- | Text at 'sp'.
sp0 :: Text -> IR.Inline
sp0 = IR.Text sp

-- | The items of a text in the environment.
compose :: ComposeEnv -> Text -> [Item]
compose env t = fst (composeInlines env [sp0 t])
