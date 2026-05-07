-- | Shell completion script generator for the nihongo CLI.
--
--   Each shell's script invokes the `nihongo` binary's
--   `--bash-completion-index` / `--bash-completion-word` protocol (provided
--   by optparse-applicative) at completion time. We do not call the
--   script-generator helpers directly here, so this module does not need to
--   know about the parser tree at all.
module Nihongo.Cli.Completions
  ( CompletionsShell (..),
    completionsCommandParser,
    runCompletionsCommand,
  )
where

import Data.Text.IO qualified as TIO
import Nihongo.Prelude ()
import Options.Applicative

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
          """
          _nihongo_completions() {
              local CMDLINE
              local IFS=$'\\n'
              CMDLINE=(--bash-completion-index $COMP_CWORD)

              for arg in ${COMP_WORDS[@]}; do
                  CMDLINE=(${CMDLINE[@]} --bash-completion-word "$arg")
              done

              COMPREPLY=( $(nihongo "${CMDLINE[@]}" 2>/dev/null) )
          }

          complete -o filenames -F _nihongo_completions nihongo
          """
        Zsh ->
          """
          #compdef nihongo

          _nihongo() {
              local -a completions
              local CMDLINE
              local IFS=$'\\n'

              CMDLINE=(--bash-completion-enriched --bash-completion-index $((CURRENT - 1)))

              for arg in ${words[@]}; do
                  CMDLINE=(${CMDLINE[@]} --bash-completion-word "$arg")
              done

              local line
              for line in $(nihongo "${CMDLINE[@]}" 2>/dev/null); do
                  local word=${line%%$'\\t'*}
                  local desc=${line#*$'\\t'}
                  if [[ "$word" != "$desc" ]]; then
                      completions+=("${word//:/\\\\:}:${desc}")
                  else
                      completions+=("$word")
                  fi
              done

              if [[ ${#completions[@]} -gt 0 ]]; then
                  _describe 'nihongo' completions
              fi
          }

          _nihongo
          """
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
