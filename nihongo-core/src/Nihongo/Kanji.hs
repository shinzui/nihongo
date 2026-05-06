-- | Kanji newtype with a smart constructor that restricts construction to
--   characters in the CJK Unified Ideographs (and Ext A) blocks plus the
--   Hiragana and Katakana blocks. KanjiVG covers all of those.
module Nihongo.Kanji
  ( Kanji,
    unKanji,
    mkKanji,
    kanjiCodepointHex,
    KanjiError (..),
    KanjiParseError (..),
    parseKanjis,
    renderKanjiParseError,
  )
where

import Data.Char (isSpace, ord)
import Data.List.NonEmpty qualified as NE
import Data.Text qualified as Text
import Nihongo.Prelude
import Numeric (showHex)

newtype Kanji = Kanji {unKanji :: Char}
  deriving stock (Eq, Show)

data KanjiError
  = KanjiOutOfRange !Char
  deriving stock (Eq, Show)

-- | Smart constructor. Accepts characters in:
--     * CJK Unified Ideographs        U+4E00 – U+9FFF
--     * CJK Unified Ideographs Ext A  U+3400 – U+4DBF
--     * Hiragana                      U+3040 – U+309F
--     * Katakana                      U+30A0 – U+30FF
--   Rejects anything else.
mkKanji :: Char -> Either KanjiError Kanji
mkKanji c
  | isInRange = Right (Kanji c)
  | otherwise = Left (KanjiOutOfRange c)
  where
    cp = ord c
    isInRange =
      (cp >= 0x4E00 && cp <= 0x9FFF)
        || (cp >= 0x3400 && cp <= 0x4DBF)
        || (cp >= 0x3040 && cp <= 0x309F)
        || (cp >= 0x30A0 && cp <= 0x30FF)

-- | Render a 'Kanji' as the 5-digit lowercase hex codepoint KanjiVG uses for
--   filenames. e.g. @kanjiCodepointHex (Kanji '漢') == "06f22"@.
kanjiCodepointHex :: Kanji -> Text
kanjiCodepointHex (Kanji c) =
  Text.pack (pad 5 (showHex (ord c) ""))
  where
    pad n s = replicate (n - length s) '0' <> s

-- | Failure modes reported by 'parseKanjis'.
data KanjiParseError
  = -- | Input contained no non-whitespace characters.
    KpeEmpty
  | -- | Input contained a character outside the accepted Japanese ranges.
    KpeNotJapanese !Char
  deriving stock (Eq, Show)

-- | Parse a 'Text' word into one or more 'Kanji', preserving input order.
--
--   Whitespace is stripped before validation, so @\"食 べ る\"@ and
--   @\"食べる\"@ produce the same three-character result. The first
--   non-Japanese character (after whitespace removal) aborts parsing with
--   'KpeNotJapanese'; an entirely-whitespace or empty input yields
--   'KpeEmpty'.
parseKanjis :: Text -> Either KanjiParseError (NonEmpty Kanji)
parseKanjis raw =
  let stripped = Text.filter (not . isSpace) raw
   in case Text.unpack stripped of
        [] -> Left KpeEmpty
        (c : cs) -> do
          k <- foldChar c
          ks <- traverse foldChar cs
          Right (k NE.:| ks)
  where
    foldChar c = case mkKanji c of
      Left (KanjiOutOfRange ch) -> Left (KpeNotJapanese ch)
      Right k -> Right k

-- | Render a 'KanjiParseError' as a user-facing message suitable for stderr.
renderKanjiParseError :: KanjiParseError -> Text
renderKanjiParseError KpeEmpty =
  "expected at least one Japanese character"
renderKanjiParseError (KpeNotJapanese c) =
  "not a Japanese character: " <> Text.singleton c
