-- | Dispatcher for the @nihongo kanji ...@ subcommand group. The group
--   currently exposes only @kanji show@; future plans (e.g. @kanji
--   find@) will extend the 'KanjiCommand' ADT and the 'kanjiParser'
--   block.
module Nihongo.Cli.Commands.Kanji
  ( KanjiCommand (..),
    kanjiParser,
    runKanji,
  )
where

import Nihongo.Cli.Commands.Kanji.Png qualified as Png
import Nihongo.Cli.Commands.Kanji.Show qualified as Show
import Nihongo.Prelude ()
import Options.Applicative
  ( Parser,
    command,
    hsubparser,
    info,
    progDesc,
  )

data KanjiCommand
  = KShow !Show.ShowCommand
  | KPng !Png.PngCommand
  deriving stock (Show, Eq)

kanjiParser :: Parser KanjiCommand
kanjiParser =
  hsubparser
    ( command
        "show"
        ( info
            (KShow <$> Show.showParser)
            (progDesc "Display stroke order for a kanji")
        )
        <> command
          "png"
          ( info
              (KPng <$> Png.pngParser)
              (progDesc "Print the path to a cached PNG of a kanji's stroke order")
          )
    )

runKanji :: KanjiCommand -> IO ()
runKanji (KShow c) = Show.runShow c
runKanji (KPng c) = Png.runPng c
