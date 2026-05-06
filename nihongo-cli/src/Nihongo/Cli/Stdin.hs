-- | Detect and consume piped stdin for CLI subcommands.
--
--   `getTextInput` is the workhorse: given an optional positional argument it
--   returns the argument if supplied, otherwise the trimmed contents of stdin
--   if stdin is piped, otherwise `Nothing`. Use `Data.Text.IO.getContents` to
--   avoid the locale-decoding problems of `pack <$> hGetContents stdin`.
module Nihongo.Cli.Stdin
  ( isStdinPiped
  , getTextInput
  ) where

import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import System.IO (hIsTerminalDevice, stdin)

import Nihongo.Prelude

isStdinPiped :: IO Bool
isStdinPiped = not <$> hIsTerminalDevice stdin

getTextInput :: Maybe Text -> IO (Maybe Text)
getTextInput (Just t) = pure (Just t)
getTextInput Nothing = do
  piped <- isStdinPiped
  if piped
    then do
      contents <- TIO.getContents
      let trimmed = Text.strip contents
      pure (if Text.null trimmed then Nothing else Just trimmed)
    else pure Nothing
