-- | Shell completion script generator for the nihongo CLI.
--
--   Each shell's script invokes the `nihongo` binary's
--   `--bash-completion-index` / `--bash-completion-word` protocol (provided
--   by optparse-applicative) at completion time. We do not call the
--   script-generator helpers directly here, so this module does not need to
--   know about the parser tree at all.
module Nihongo.Cli.Completions
  ( CompletionsShell (..)
  , completionsCommandParser
  , runCompletionsCommand
  ) where

import Data.Text.IO qualified as TIO
import Options.Applicative

import Nihongo.Prelude ()

data CompletionsShell = Bash | Zsh | Fish
  deriving stock (Show, Eq)

completionsCommandParser :: Parser CompletionsShell
completionsCommandParser =
  argument
    (maybeReader parseShell)
    (metavar "SHELL" <> help "Target shell: bash | zsh | fish")
  where
    parseShell "bash" = Just Bash
    parseShell "zsh" = Just Zsh
    parseShell "fish" = Just Fish
    parseShell _ = Nothing

runCompletionsCommand :: CompletionsShell -> IO ()
runCompletionsCommand sh = do
  let progName = "nihongo"
  let scriptText = case sh of
        Bash ->
          "_nihongo_completions() {\n"
            <> "  local CMDLINE\n"
            <> "  local IFS=$'\\n'\n"
            <> "  CMDLINE=(--bash-completion-index $COMP_CWORD)\n"
            <> "  for arg in \"${COMP_WORDS[@]}\"; do\n"
            <> "    CMDLINE=(\"${CMDLINE[@]}\" --bash-completion-word \"$arg\")\n"
            <> "  done\n"
            <> "  COMPREPLY=( $(\""
            <> progName
            <> "\" \"${CMDLINE[@]}\") )\n"
            <> "}\n"
            <> "complete -o filenames -F _nihongo_completions "
            <> progName
            <> "\n"
        Zsh ->
          "#compdef "
            <> progName
            <> "\n"
            <> "_nihongo() {\n"
            <> "  local words completions\n"
            <> "  read -cA words\n"
            <> "  if [[ \"${words[$CURRENT]}\" == --* ]]; then\n"
            <> "    completions=($(\""
            <> progName
            <> "\" --bash-completion-index $CURRENT --bash-completion-word \"${words[@]}\"))\n"
            <> "  else\n"
            <> "    completions=($(\""
            <> progName
            <> "\" --bash-completion-index $CURRENT --bash-completion-word \"${words[@]}\"))\n"
            <> "  fi\n"
            <> "  reply=( \"${(ps:\\n:)completions}\" )\n"
            <> "}\n"
            <> "compctl -K _nihongo "
            <> progName
            <> "\n"
        Fish ->
          "function _nihongo_completion\n"
            <> "  set -l cmd (commandline -opc) (commandline -ct)\n"
            <> "  "
            <> progName
            <> " --bash-completion-index (count $cmd) --bash-completion-word $cmd\n"
            <> "end\n"
            <> "complete -c "
            <> progName
            <> " -f -a '(_nihongo_completion)'\n"
  TIO.putStr scriptText
