-- | Hidden internal subcommand @image-debug-render <SVG_PATH>@ that
--   exercises 'Nihongo.Terminal.Image.displaySvg' end-to-end. Like
--   "Nihongo.Cli.Commands.KanjiDebug", this module is temporary
--   scaffolding introduced by EP-4 and removed when EP-5 lands the
--   user-facing @kanji show@ command.
module Nihongo.Cli.Commands.ImageDebug
  ( ImageDebugCommand (..)
  , imageDebugParser
  , runImageDebug
  ) where

import Data.Text qualified as Text
import Options.Applicative
  ( Parser
  , argument
  , help
  , long
  , metavar
  , str
  , switch
  )

import Nihongo.Prelude
import Nihongo.Terminal.Image
  ( detectImageCapabilityWithOverride
  , displaySvg
  )

data ImageDebugCommand = ImageDebugCommand
  { idcSvgPath :: !FilePath
  , idcNoImages :: !Bool
  }
  deriving stock (Show, Eq)

imageDebugParser :: Parser ImageDebugCommand
imageDebugParser =
  ImageDebugCommand
    <$> argument str (metavar "SVG_PATH" <> help "Path to a KanjiVG SVG file")
    <*> switch (long "no-images" <> help "Force the placeholder fallback")

runImageDebug :: ImageDebugCommand -> IO ()
runImageDebug (ImageDebugCommand path noImages) = do
  cap <- detectImageCapabilityWithOverride noImages
  displaySvg cap (Text.pack ("@" <> path)) path
