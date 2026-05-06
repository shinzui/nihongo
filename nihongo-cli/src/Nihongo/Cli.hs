-- | Top-level CLI entry point for nihongo.
--
--   `runCli` parses argv, supports `--version`, and dispatches to one of
--   three subcommands: `hello` (placeholder demonstrating stdin
--   auto-detection), `help` (topic browser with width-aware wrapping), and
--   `completions` (shell completion script generator).
module Nihongo.Cli
  ( runCli
  ) where

import Data.Foldable (traverse_)
import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import Options.Applicative

import Nihongo.Cli.Commands.Kanji qualified as Kanji
import Nihongo.Cli.Completions qualified as Completions
import Nihongo.Cli.Help qualified as Help
import Nihongo.Cli.Stdin qualified as Stdin
import Nihongo.Cli.Version (versionInfoOption)
import Nihongo.Prelude

data Command
  = CmdHello !(Maybe Text)
  | CmdHelp !Help.HelpCommand
  | CmdCompletions !Completions.CompletionsShell
  | CmdKanji !Kanji.KanjiCommand
  deriving stock (Generic, Show, Eq)

runCli :: IO ()
runCli = do
  cmd <- execParser parserInfo
  runCommand cmd
  where
    parserInfo =
      info
        (commandParser <**> helper <**> versionInfoOption)
        ( fullDesc
            <> progDesc "Terminal-first Japanese learning companion."
            <> header "nihongo - kanji, vocabulary, readings, stroke order, and grammar from the command line."
        )

commandParser :: Parser Command
commandParser =
  hsubparser
    ( command
        "hello"
        ( info
            helloParser
            (progDesc "Print a greeting (placeholder example)")
        )
        <> command
          "help"
          ( info
              (CmdHelp <$> Help.helpCommandParser)
              (progDesc "Show help topics. Use `help` for the list, `help <topic>` to read one.")
          )
        <> command
          "completions"
          ( info
              (CmdCompletions <$> Completions.completionsCommandParser)
              (progDesc "Print a shell completion script (bash | zsh | fish)")
          )
        <> command
          "kanji"
          ( info
              (CmdKanji <$> Kanji.kanjiParser)
              (progDesc "Look up kanji: stroke order, components, readings")
          )
    )

helloParser :: Parser Command
helloParser =
  CmdHello <$> optional (strOption (long "name" <> metavar "NAME" <> help "Whom to greet"))

runCommand :: Command -> IO ()
runCommand (CmdHello mName) = do
  resolved <- Stdin.getTextInput mName
  let target = fromMaybe (Text.pack "nihongo") resolved
  traverse_ TIO.putStrLn [Text.pack "Hello, " <> target <> Text.pack "!"]
runCommand (CmdHelp hc) = Help.runHelpCommand hc
runCommand (CmdCompletions sh) = Completions.runCompletionsCommand sh
runCommand (CmdKanji c) = Kanji.runKanji c
