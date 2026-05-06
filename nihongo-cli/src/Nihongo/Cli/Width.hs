-- | Terminal-width resolution and paragraph-aware text wrapping.
--
--   `resolveWidth` returns `Nothing` when stdout is not a TTY (so piped
--   output stays byte-stable) and otherwise queries `terminal-size` via
--   `ioctl(TIOCGWINSZ)` — never `ansi-terminal`'s cursor-position trick,
--   which writes escape sequences into stdout and can hang under captured
--   harnesses.
--
--   `wrapText` splits on blank-line paragraph boundaries; paragraphs whose
--   non-empty lines all start with two spaces are treated as verbatim and
--   emitted unchanged. Other paragraphs are greedy-packed within the width.
module Nihongo.Cli.Width
  ( resolveWidth
  , wrapText
  ) where

import Data.Text (Text)
import Data.Text qualified as Text
import System.Console.Terminal.Size (Window (..), size)
import System.IO (hIsTerminalDevice, stdout)

-- | Cap auto-detected width at this many columns for readability.
maxAutoWidth :: Int
maxAutoWidth = 140

resolveWidth :: Maybe Int -> IO (Maybe Int)
resolveWidth (Just n) = pure (Just n)
resolveWidth Nothing = do
  isTty <- hIsTerminalDevice stdout
  if not isTty
    then pure Nothing
    else do
      mw <- size
      pure $ case mw of
        Nothing -> Nothing
        Just (Window {width = w}) -> Just (min w maxAutoWidth)

wrapText :: Int -> Text -> Text
wrapText w input = Text.intercalate "\n\n" (map wrapPara paragraphs)
  where
    paragraphs = Text.splitOn "\n\n" input
    wrapPara p
      | isVerbatim p = p
      | otherwise = greedyWrap w (Text.words p)
    isVerbatim p =
      all
        (\l -> Text.null l || Text.isPrefixOf "  " l)
        (Text.splitOn "\n" p)

greedyWrap :: Int -> [Text] -> Text
greedyWrap w = Text.intercalate "\n" . go [] 0
  where
    go acc _ [] = [Text.unwords (reverse acc)]
    go acc col (x : xs)
      | null acc = go [x] (Text.length x) xs
      | col + 1 + Text.length x <= w =
          go (x : acc) (col + 1 + Text.length x) xs
      | otherwise =
          Text.unwords (reverse acc) : go [x] (Text.length x) xs
