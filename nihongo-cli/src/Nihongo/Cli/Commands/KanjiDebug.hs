-- | Hidden internal subcommand `kanji-debug-path <CHAR>` that prints the
--   resolved KanjiVG SVG path for a single character. This module is
--   temporary scaffolding introduced by EP-2 to validate the lookup
--   end-to-end; EP-5's `kanji show` subsumes it and the module is removed
--   when EP-5 lands.
module Nihongo.Cli.Commands.KanjiDebug
  ( KanjiDebugCommand (..)
  , kanjiDebugParser
  , runKanjiDebug
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
  , str
  , strOption
  )
import System.Exit (exitFailure)
import System.IO qualified as IO

import Nihongo.Kanji (KanjiError (..), mkKanji)
import Nihongo.Kanji.KanjiVg (findStrokeSvg, resolveKanjiVgRoot)
import Nihongo.Prelude

data KanjiDebugCommand = KanjiDebugCommand
  { kdcInput :: !Text
  , kdcRootOverride :: !(Maybe FilePath)
  }
  deriving stock (Show, Eq)

kanjiDebugParser :: Parser KanjiDebugCommand
kanjiDebugParser =
  KanjiDebugCommand
    <$> argument str (metavar "CHAR" <> help "Single Japanese character")
    <*> optional
      ( strOption
          ( long "kanjivg-dir"
              <> metavar "PATH"
              <> help "Override the KanjiVG root directory"
          )
      )

runKanjiDebug :: KanjiDebugCommand -> IO ()
runKanjiDebug (KanjiDebugCommand input override) =
  case Text.uncons input of
    Nothing -> die "expected a single character"
    Just (c, rest)
      | not (Text.null rest) -> die "expected a single character (got more)"
      | otherwise ->
          case mkKanji c of
            Left (KanjiOutOfRange ch) ->
              die ("not a Japanese character: " <> Text.singleton ch)
            Right k -> do
              mroot <- resolveKanjiVgRoot override
              case mroot of
                Nothing -> die "KanjiVG root not found; see --help"
                Just r -> do
                  mp <- findStrokeSvg r k
                  case mp of
                    Just p -> TIO.putStrLn (Text.pack p)
                    Nothing -> die "kanji has no entry in this KanjiVG checkout"
  where
    die msg = TIO.hPutStrLn IO.stderr msg >> exitFailure
