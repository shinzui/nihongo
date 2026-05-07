-- | The @nihongo alias@ subcommand surface.
--
--   Today this exposes only @nihongo alias list@ (also the default action
--   when no subcommand is supplied). The list view prints the resolved
--   alias map as a sorted, padded @name = expansion@ table.
module Nihongo.Cli.Alias
  ( AliasCommand (..),
    aliasCommandParser,
    handleAliasCommand,
    renderAliasTable,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Nihongo.Config.Load (loadNihongoConfig, resolveAliases)
import Nihongo.Config.Types (ConfigError (..))
import Nihongo.Prelude
import Options.Applicative
import System.Exit (ExitCode (..), exitWith)
import System.IO (stderr)

data AliasCommand = AliasList
  deriving stock (Show, Eq)

aliasCommandParser :: Parser AliasCommand
aliasCommandParser =
  hsubparser
    ( command
        "list"
        ( info
            (pure AliasList <**> helper)
            (progDesc "List configured aliases")
        )
    )
    <|> pure AliasList

handleAliasCommand :: AliasCommand -> IO ()
handleAliasCommand AliasList = do
  result <- loadNihongoConfig
  case result of
    Left err -> do
      TIO.hPutStrLn stderr ("nihongo: config error:\n" <> renderError err)
      exitWith (ExitFailure 1)
    Right cfg -> TIO.putStr (renderAliasTable (resolveAliases cfg))

renderError :: ConfigError -> Text
renderError = \case
  ConfigFileReadError p msg ->
    "  failed to read " <> T.pack p <> ": " <> msg
  ConfigParseError msg ->
    T.unlines (map ("  " <>) (T.lines msg))

-- | One line per entry, sorted ascending by alias name. Each name is
--   padded to the longest name length so the @=@ separators align.
--   Returns @"No aliases configured.\n"@ for an empty map.
renderAliasTable :: Map Text Text -> Text
renderAliasTable m
  | Map.null m = "No aliases configured.\n"
  | otherwise =
      let entries = Map.toAscList m
          width = maximum (map (T.length . fst) entries)
       in T.unlines [pad width name <> " = " <> expansion | (name, expansion) <- entries]
  where
    pad w name = name <> T.replicate (w - T.length name) " "
