-- | CJK Stroke type taxonomy. Maps the canonical CJK Stroke characters
--   (U+31C0–U+31E3) used in KanjiVG's @kvg:type@ attribute to short English
--   descriptions. Variant suffixes (a single ASCII letter trailing the
--   stroke character, e.g. @"㇑a"@) are preserved separately so callers can
--   render the variant if they want, while base lookup ignores them.
module Nihongo.Kanji.StrokeType
  ( StrokeType (..),
    parseStrokeType,
    describeStrokeType,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Nihongo.Prelude

-- | A normalised stroke type: the base CJK Stroke character (e.g. @'㇐'@)
--   plus the optional variant suffix some KanjiVG entries carry.
data StrokeType = StrokeType
  { baseChar :: !Char,
    variant :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

-- | Parse the contents of a @kvg:type@ attribute. The attribute is one CJK
--   Stroke character optionally followed by ASCII letters.
parseStrokeType :: Text -> Maybe StrokeType
parseStrokeType raw =
  case Text.uncons raw of
    Nothing -> Nothing
    Just (c, rs) ->
      Just (StrokeType c (if Text.null rs then Nothing else Just rs))

-- | English description for a base stroke character. Returns 'Nothing' if
--   the character is not a known CJK Stroke. Variant suffixes are ignored.
describeStrokeType :: StrokeType -> Maybe Text
describeStrokeType (StrokeType c _) = Map.lookup c table

table :: Map Char Text
table =
  Map.fromList
    [ ('\x31C0', "rising"),
      ('\x31C1', "curve-down"),
      ('\x31C2', "slant"),
      ('\x31C3', "hook"),
      ('\x31C4', "wave"),
      ('\x31C5', "down-stroke"),
      ('\x31C6', "turn"),
      ('\x31C7', "turn-rise"),
      ('\x31C8', "curve-rise"),
      ('\x31C9', "curve-rise-hook"),
      ('\x31CA', "turn-down"),
      ('\x31CB', "turn-rise-hook"),
      ('\x31CC', "turn-curve-rise"),
      ('\x31CD', "curve-down-rise"),
      ('\x31CE', "turn-curve"),
      ('\x31CF', "right-falling"),
      ('\x31D0', "horizontal"),
      ('\x31D1', "vertical"),
      ('\x31D2', "left-falling"),
      ('\x31D3', "left-falling-curve"),
      ('\x31D4', "dot"),
      ('\x31D5', "turn-down"),
      ('\x31D6', "hook-up"),
      ('\x31D7', "turn-down-hook"),
      ('\x31D8', "turn-curve-up-down"),
      ('\x31D9', "vertical-hook"),
      ('\x31DA', "vertical-hook-down"),
      ('\x31DB', "turn-up-hook"),
      ('\x31DC', "turn-curve-down"),
      ('\x31DD', "curve-up"),
      ('\x31DE', "turn-curve"),
      ('\x31DF', "curve-up-hook"),
      ('\x31E0', "curve-down-hook"),
      ('\x31E1', "turn-curve-rise-hook"),
      ('\x31E2', "turn-down-curve"),
      ('\x31E3', "hook-down")
    ]
