-- | The user-facing @nihongo kanji png <KANJI>@ subcommand. Resolves a
--   single kanji (positional argument or stdin) to the absolute path of a
--   cached PNG of its KanjiVG glyph and prints that path on stdout.
--   Designed to be safe in shell substitution: stdout carries only the
--   path on success, and is left empty on any error.
module Nihongo.Cli.Commands.Kanji.Png
  ( PngCommand (..)
  , pngParser
  , runPng
  ) where

import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import Options.Applicative
  ( Parser
  , argument
  , help
  , long
  , metavar
  , optional
  , parserOptionGroup
  , str
  , strOption
  )
import System.Exit (exitFailure)
import System.IO qualified as IO

import Nihongo.Cli.Stdin qualified as Stdin
import Nihongo.Kanji (Kanji, KanjiError (..), mkKanji)
import Nihongo.Kanji.Png
  ( KanjiPngOptions (..)
  , kanjiPngPath
  , renderKanjiPngError
  )
import Nihongo.Prelude

data PngCommand = PngCommand
  { pngInput :: !(Maybe Text)
  , pngKanjivgDir :: !(Maybe FilePath)
  }
  deriving stock (Show, Eq)

pngParser :: Parser PngCommand
pngParser =
  PngCommand
    <$> optional
      ( argument
          str
          ( metavar "KANJI"
              <> help "A single Japanese character. Reads from stdin if omitted."
          )
      )
    <*> parserOptionGroup "Source options" sourceGroup
  where
    sourceGroup =
      optional
        ( strOption
            ( long "kanjivg-dir"
                <> metavar "PATH"
                <> help "Override the KanjiVG checkout directory."
            )
        )

runPng :: PngCommand -> IO ()
runPng (PngCommand inputArg dirOverride) = do
  mInput <- Stdin.getTextInput inputArg
  kanji <- case mInput of
    Nothing -> die "expected a kanji as a positional argument or on stdin"
    Just t -> readSingleKanji t
  result <- kanjiPngPath (KanjiPngOptions dirOverride) kanji
  case result of
    Left err -> die (renderKanjiPngError err)
    Right path -> TIO.putStrLn (Text.pack path)

readSingleKanji :: Text -> IO Kanji
readSingleKanji raw =
  case Text.uncons (Text.strip raw) of
    Nothing -> die "expected a single character"
    Just (c, rest)
      | not (Text.null rest) -> die "expected a single character (got more)"
      | otherwise ->
          case mkKanji c of
            Left (KanjiOutOfRange ch) ->
              die ("not a Japanese character: " <> Text.singleton ch)
            Right k -> pure k

die :: Text -> IO a
die msg = do
  TIO.hPutStrLn IO.stderr msg
  exitFailure
