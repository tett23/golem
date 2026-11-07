{- | The URL of a link to an external URL (docs/adr ADR 0182): the checks
the evaluator applies to [link] and the validation to the IR of plugins
and functions, in one place.
-}
module Golem.Doc.Url
  ( UrlProblem (..),
    checkUrl,
    urlProblemMessage,
    linkElements,
  )
where

import Data.Char (GeneralCategory (..), generalCategory, isAscii, isAsciiLower, isAsciiUpper, isDigit, isHexDigit, ord)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR

-- | Why a URL cannot be the URL of a link, in the order of the checks.
data UrlProblem
  = -- | not of the form of an absolute URI (RFC 3986, with the characters of RFC 3987): G02125
    UrlMalformed
  | -- | the scheme is not http or https: G02126
    UrlScheme
  | -- | the host has a character that is not ASCII: G02127
    UrlHost
  deriving stock (Eq, Show, Enum, Bounded)

{- | The first check a URL fails, or Nothing. The form: the characters of
RFC 3986 (and those of RFC 3987 outside ASCII), no space or control
character, two hexadecimal digits after each @%@, at most one @#@, a
scheme of RFC 3986 before the first @:@ when that comes before a @/@,
@?@ or @#@, and @//@ and a host that is not empty after a scheme that
has @//@ or is http or https. Brackets only around the host. Then the
scheme, http or https in any case, and then a host in ASCII.
-}
checkUrl :: Text -> Maybe UrlProblem
checkUrl u = case parts u of
  Nothing -> Just UrlMalformed
  Just (scheme, host)
    | maybe True ((`notElem` ["http", "https"]) . T.toLower) scheme -> Just UrlScheme
    | maybe False (T.any (not . isAscii)) host -> Just UrlHost
    | otherwise -> Nothing

-- | The scheme and the host of a URL of the form, or Nothing.
parts :: Text -> Maybe (Maybe Text, Maybe Text)
parts u
  | T.null u = Nothing
  | not (T.all allowed u) = Nothing
  | not (percentOk (T.unpack u)) = Nothing
  | T.count "#" u > 1 = Nothing
  | otherwise = case T.breakOn ":" u of
      (pre, rest)
        | not (T.null rest), not (T.any (`elem` ("/?#" :: String)) pre) ->
            if validScheme pre then afterScheme pre (T.drop 1 rest) else Nothing
        | otherwise -> if T.any (`elem` ("[]" :: String)) u then Nothing else Just (Nothing, Nothing)
  where
    afterScheme scheme rest = case T.stripPrefix "//" rest of
      Just r -> do
        let (authority, tailPart) = T.break (`elem` ("/?#" :: String)) r
        h <- hostOf authority
        if T.any (`elem` ("[]" :: String)) tailPart || privateOutsideQuery tailPart then Nothing else Just (Just scheme, Just h)
      Nothing
        | T.toLower scheme `elem` ["http", "https"] -> Nothing
        | T.any (`elem` ("[]" :: String)) rest -> Nothing
        | otherwise -> Just (Just scheme, Nothing)
    hostOf authority =
      let hostPort = case T.breakOnEnd "@" authority of
            ("", a) -> a
            (_, a) -> a
          userinfo = T.dropEnd (T.length hostPort) authority
          (host, port) = case T.uncons hostPort of
            Just ('[', _) -> let (a, b) = T.breakOn "]" hostPort in (a <> T.take 1 b, T.drop 1 b)
            _ -> T.breakOn ":" hostPort
          portOk = T.null port || (T.head port == ':' && T.all isDigit (T.drop 1 port))
          ipLiteral = case T.stripPrefix "[" host >>= T.stripSuffix "]" of
            Just inner -> not (T.null inner) && T.all (\c -> isHexDigit c || c `elem` (":.vV" :: String)) inner
            Nothing -> not (T.any (`elem` ("[]" :: String)) host)
       in if not (T.null host) && portOk && ipLiteral && not (T.any (`elem` ("[]" :: String)) userinfo) && not (privateOutsideQuery authority)
            then Just host
            else Nothing
    -- the private use characters of RFC 3987 stand only in the query
    privateOutsideQuery t =
      let (beforeFragment, fragment) = T.breakOn "#" t
          path = T.takeWhile (/= '?') beforeFragment
       in T.any private path || T.any private fragment

validScheme :: Text -> Bool
validScheme s = case T.uncons s of
  Just (c, rest) -> asciiAlpha c && T.all (\x -> asciiAlpha x || isDigit x || x `elem` ("+-." :: String)) rest
  Nothing -> False
  where
    asciiAlpha x = isAsciiLower x || isAsciiUpper x

-- | A character a URL may hold: of RFC 3986 in ASCII, of RFC 3987 outside it.
allowed :: Char -> Bool
allowed c
  | isAscii c = isAsciiLower c || isAsciiUpper c || isDigit c || c `elem` ("-._~:/?#[]@!$&'()*+,;=%" :: String)
  | otherwise = (ucschar c || private c) && generalCategory c `notElem` [Space, LineSeparator, ParagraphSeparator, Format, Control]

-- | The ucschar of RFC 3987.
ucschar :: Char -> Bool
ucschar c =
  let n = ord c
   in (n >= 0xA0 && n <= 0xD7FF)
        || (n >= 0xF900 && n <= 0xFDCF)
        || (n >= 0xFDF0 && n <= 0xFFEF)
        || (n >= 0x10000 && n <= 0xEFFFD && n `mod` 0x10000 <= 0xFFFD)

-- | The iprivate of RFC 3987.
private :: Char -> Bool
private c =
  let n = ord c
   in (n >= 0xE000 && n <= 0xF8FF) || (n >= 0xF0000 && n <= 0xFFFFD) || (n >= 0x100000 && n <= 0x10FFFD)

percentOk :: String -> Bool
percentOk = \case
  [] -> True
  '%' : a : b : rest | isAscii a && isHexDigit a && isAscii b && isHexDigit b -> percentOk rest
  '%' : _ -> False
  _ : rest -> percentOk rest

-- | The message of a problem of a URL (G02125, G02126, G02127).
urlProblemMessage :: UrlProblem -> Text -> Text
urlProblemMessage p u = case p of
  UrlMalformed -> "URL の形が誤っています: " <> u
  UrlScheme -> "リンクにできる URL は http と https だけです: " <> u
  UrlHost -> "URL のホストは ASCII で書きます: " <> u

{- | The elements in inlines that are links themselves, by the names of
their commands (G02128): links, references, notes, sidenotes and
citations, inside character styles, colours, kenten and the bases of
ruby; the inside of one is not searched.
-}
linkElements :: [InlineF r] -> [Text]
linkElements = concatMap $ \case
  Link {} -> ["link"]
  Ref _ k _ -> [case k of RefNumber -> "ref-number"; RefTitle -> "ref-title"; RefPage -> "ref-page"]
  Note {} -> ["note"]
  Sidenote {} -> ["sidenote"]
  Cite {} -> ["cite"]
  Ruby _ _ segs -> concatMap (linkElements . rsBase) segs
  Kenten _ _ xs -> linkElements xs
  Color _ _ xs -> linkElements xs
  CharStyle _ _ xs -> linkElements xs
  _ -> []
