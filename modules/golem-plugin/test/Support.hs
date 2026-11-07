-- | The helpers that the tests of golem-plugin share (docs/adr/0173).
module Support
  ( cbor,
    callSpan,
  )
where

import Codec.CBOR.Term (Term, encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Data.ByteString (ByteString)
import Golem.Syntax.Span (FileId (..), SrcSpan, mkSpan)

-- | The bytes of the CBOR of a term.
cbor :: Term -> ByteString
cbor = toStrictByteString . encodeTerm

-- | The span of the call of a plugin in the tests.
callSpan :: SrcSpan
callSpan = mkSpan (FileId 1) 10 20
