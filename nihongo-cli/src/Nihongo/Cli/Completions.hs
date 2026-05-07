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
runCompletionsCommand sh =
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
          """
          # Disable file completion by default
          complete -c nihongo -f

          function __nihongo_complete
              set -l tokens (commandline -cop)
              set -l current (commandline -ct)
              set -l index (count $tokens)

              set -l args --bash-completion-enriched --bash-completion-index $index
              for token in $tokens
                  set args $args --bash-completion-word $token
              end
              set args $args --bash-completion-word "$current"

              for line in (nihongo $args 2>/dev/null)
                  # Split on tab: word<TAB>description
                  set -l parts (string split \\t -- $line)
                  if test (count $parts) -ge 2
                      printf '%s\\t%s\\n' $parts[1] $parts[2]
                  else
                      echo $line
                  end
              end
          end

          complete -c nihongo -a '(__nihongo_complete)'
          """
   in TIO.putStr scriptText
