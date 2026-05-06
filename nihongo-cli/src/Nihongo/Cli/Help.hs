{-# LANGUAGE TemplateHaskell #-}

-- | Help-topic browser for the nihongo CLI.
--
--   Topics live under nihongo-cli/help/<name>.md and are compiled into the
--   binary at build time via `Data.FileEmbed.embedStringFile`. Note: cabal
--   does NOT recognise embedded file changes for relinking — after editing
--   a topic you must `touch` this module or `cabal clean && cabal build all`
--   to force a rebuild.
--
--   The parser shape `buildHelp <$> optional topicArg <*> widthOption`
--   keeps `topicArg` and `widthOption` as siblings of the same applicative
--   so optparse-applicative has no `<|>` branch to commit to prematurely.
--   This avoids the "Missing TOPIC" parser-shape trap when running
--   `nihongo help --width 60`. See haskell-jitsurei/cli/help-width.md.
module Nihongo.Cli.Help
  ( HelpTopic (..),
    HelpCommand (..),
    helpTopics,
    helpCommandParser,
    runHelpCommand,
  )
where

import Data.FileEmbed (embedStringFile)
import Data.Foldable (for_)
import Data.List qualified as List
import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import Nihongo.Cli.Width (resolveWidth, wrapText)
import Nihongo.Prelude
import Options.Applicative

data HelpTopic = HelpTopic
  { topicName :: !Text,
    topicDescription :: !Text,
    topicContent :: !Text
  }
  deriving stock (Generic, Show, Eq)

helpTopics :: [HelpTopic]
helpTopics =
  [ HelpTopic "about" "Project overview" $(embedStringFile "help/about.md"),
    HelpTopic "kanji-png" "kanji png command reference" $(embedStringFile "help/kanji-png.md"),
    HelpTopic "kanji-show" "kanji show command reference" $(embedStringFile "help/kanji-show.md"),
    HelpTopic "width-demo" "Width-handling fixture topic" $(embedStringFile "help/width-demo.md")
  ]

data HelpCommand
  = ListTopics
  | ShowTopic !Text !(Maybe Int)
  deriving stock (Generic, Show, Eq)

helpCommandParser :: Parser HelpCommand
helpCommandParser =
  buildHelp <$> optional topicArg <*> widthOption
  where
    topicArg = strArgument (metavar "TOPIC" <> help "Help topic to display")
    widthOption =
      optional $
        option
          auto
          ( long "width"
              <> metavar "COLUMNS"
              <> help "Wrap output to this many columns"
          )
    buildHelp Nothing _ = ListTopics
    buildHelp (Just t) w = ShowTopic t w

runHelpCommand :: HelpCommand -> IO ()
runHelpCommand ListTopics = do
  TIO.putStrLn "Available help topics:"
  for_ helpTopics $ \topic ->
    TIO.putStrLn ("  " <> topic ^. #topicName <> "  -- " <> topic ^. #topicDescription)
  TIO.putStrLn "\nRun `nihongo help <topic>` to read one."
runHelpCommand (ShowTopic name maybeW) = do
  let needle = Text.toLower name
  case List.find (\t -> Text.toLower (t ^. #topicName) == needle) helpTopics of
    Nothing ->
      TIO.putStrLn ("Unknown help topic: " <> name <> ". Run `nihongo help` for the list.")
    Just topic -> do
      mw <- resolveWidth maybeW
      let body = topic ^. #topicContent
      TIO.putStr $ case mw of
        Nothing -> body
        Just w -> wrapText w body
