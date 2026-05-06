-- | Small set of ANSI styling helpers used by nihongo CLI output.
--
--   The escape sequences are emitted directly as Text concatenation; no
--   external dependency is needed. Consumers that need to suppress ANSI
--   output (e.g. when stdout is not a TTY) must check that themselves;
--   these helpers always emit the escape codes.
module Nihongo.Pretty
  ( Color (..),
    dim,
    bold,
    colored,
  )
where

import Nihongo.Prelude

data Color = Red | Green | Yellow | Blue | Magenta | Cyan | White
  deriving stock (Eq, Show)

dim :: Text -> Text
dim t = "\ESC[2m" <> t <> "\ESC[22m"

bold :: Text -> Text
bold t = "\ESC[1m" <> t <> "\ESC[22m"

colored :: Color -> Text -> Text
colored c t = "\ESC[" <> code c <> "m" <> t <> "\ESC[39m"
  where
    code Red = "31"
    code Green = "32"
    code Yellow = "33"
    code Blue = "34"
    code Magenta = "35"
    code Cyan = "36"
    code White = "37"
