-- | Pre-parse rewriting of the argument list to support user-defined
--   command aliases declared in the @aliases { … }@ KDL block.
--
--   'expandAlias' is pure; the loader and IO live in "Nihongo.Cli" and
--   "Nihongo.Config.Load".
module Nihongo.Cli.Aliases
  ( builtinCommands,
    expandAlias,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T

-- | Top-level subcommand names registered in 'Nihongo.Cli.commandParser'.
--   Keep this list in sync when adding new commands; the test suite
--   enforces both directions of the registry/parser correspondence.
builtinCommands :: [Text]
builtinCommands =
  [ "hello",
    "help",
    "completions",
    "kanji",
    "alias"
  ]

-- | Rewrite the first positional argument according to the alias map.
--
--   Pass-through cases (no rewrite):
--
--     * Empty argv.
--     * Argv whose first token starts with @-@ (so the bash-completion
--       entry path, @--version@, and @--help@ are never touched).
--     * Argv whose first token is in 'builtinCommands' (a built-in name
--       can never be shadowed by an alias).
--
--   When the first token is a key in the alias map, the expansion is
--   split on whitespace via 'Data.Text.words' and prepended to the
--   remaining argv. Expansion is non-recursive: if the alias map
--   contains both @\"a\" -> \"b ...\"@ and @\"b\" -> \"c ...\"@,
--   invoking @[\"a\", x]@ produces @[\"b\", \"...\", x]@, not
--   @[\"c\", ...]@.
expandAlias :: Map Text Text -> [String] -> [String]
expandAlias aliasMap = \case
  [] -> []
  args@(first : rest)
    | startsWithDash first -> args
    | T.pack first `elem` builtinCommands -> args
    | otherwise -> case Map.lookup (T.pack first) aliasMap of
        Nothing -> args
        Just expansion ->
          map T.unpack (T.words expansion) <> rest
  where
    startsWithDash ('-' : _) = True
    startsWithDash _ = False
