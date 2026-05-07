-- | Top-level CLI entry point for nihongo.
--
--   `runCli` loads the user config, expands user-defined aliases against
--   the raw argv, parses the result, and dispatches to one of the
--   subcommands: `hello` (placeholder demonstrating stdin auto-detection),
--   `help` (topic browser with width-aware wrapping), `completions` (shell
--   completion script generator), or `kanji` (lookup commands).
module Nihongo.Cli
  ( runCli,
  )
where

import Data.Foldable (traverse_)
import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import Nihongo.Cli.Aliases (builtinCommands, expandAlias)
import Nihongo.Cli.Commands.Kanji qualified as Kanji
import Nihongo.Cli.Completions qualified as Completions
import Nihongo.Cli.Help qualified as Help
import Nihongo.Cli.Stdin qualified as Stdin
import Nihongo.Cli.Version (versionInfoOption)
import Nihongo.Config.Load (loadNihongoConfig, resolveAliases)
import Nihongo.Config.Types (ConfigError (..))
import Nihongo.Prelude
import Options.Applicative
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (stderr)

data Command
  = CmdHello !(Maybe Text)
  | CmdHelp !Help.HelpCommand
  | CmdCompletions !Completions.CompletionsShell
  | CmdKanji !Kanji.KanjiCommand
  deriving stock (Generic, Show, Eq)

runCli :: IO ()
runCli = do
  rawArgs <- getArgs
  expanded <- expandRawArgs rawArgs
  cmd <-
    handleParseResult $
      execParserPure (prefs showHelpOnEmpty) parserInfo expanded
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

-- | Resolve the alias map (only when the first token might actually be
--   an alias) and rewrite @argv@. Skips config IO entirely when the first
--   token is empty / dash-prefixed / a built-in command — that lets
--   @nihongo --version@, @nihongo --help@, the bash-completion entry path,
--   and every built-in subcommand keep working even if @config.kdl@ is
--   broken.
expandRawArgs :: [String] -> IO [String]
expandRawArgs args = case args of
  [] -> pure args
  (firstArg : _)
    | startsWithDash firstArg -> pure args
    | Text.pack firstArg `elem` builtinCommands -> pure args
    | otherwise -> do
        cfgRes <- loadNihongoConfig
        case cfgRes of
          Left err -> die (renderConfigError err)
          Right cfg -> pure (expandAlias (resolveAliases cfg) args)
  where
    startsWithDash ('-' : _) = True
    startsWithDash _ = False

renderConfigError :: ConfigError -> Text
renderConfigError = \case
  ConfigFileReadError p msg ->
    "  failed to read " <> Text.pack p <> ": " <> msg
  ConfigParseError msg ->
    Text.unlines (map ("  " <>) (Text.lines msg))

die :: Text -> IO a
die msg = do
  TIO.hPutStrLn stderr ("nihongo: config error:\n" <> msg)
  exitWith (ExitFailure 1)
