-- | Kanji newtype with a smart constructor that restricts construction to
--   characters in the CJK Unified Ideographs (and Ext A) blocks plus the
--   Hiragana and Katakana blocks. KanjiVG covers all of those.
module Nihongo.Kanji
  ( Kanji,
    unKanji,
    mkKanji,
    kanjiCodepointHex,
    KanjiError (..),
  )
where

import Data.Char (ord)
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
