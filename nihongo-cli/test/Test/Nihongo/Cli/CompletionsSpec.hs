module Test.Nihongo.Cli.CompletionsSpec (spec) where

import Data.Text qualified as T
import Nihongo.Cli.Completions (CompletionsShell (..), completionScript)
import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec = describe "Nihongo.Cli.Completions.completionScript" $ do
  it "Bash script registers a complete -F handler" $ do
    let s = completionScript Bash
    s `shouldSatisfy` ("_nihongo_completions()" `T.isInfixOf`)
    s `shouldSatisfy` ("--bash-completion-index $COMP_CWORD" `T.isInfixOf`)
    s `shouldSatisfy` ("complete -o filenames -F _nihongo_completions nihongo" `T.isInfixOf`)

  it "Zsh script uses #compdef and _describe with enriched protocol" $ do
    let s = completionScript Zsh
    s `shouldSatisfy` ("#compdef nihongo" `T.isInfixOf`)
    s `shouldSatisfy` ("--bash-completion-enriched" `T.isInfixOf`)
    s `shouldSatisfy` ("_describe 'nihongo' completions" `T.isInfixOf`)
    s `shouldSatisfy` ("${word//:/\\\\:}" `T.isInfixOf`)

  it "Fish script disables file completion and uses enriched protocol" $ do
    let s = completionScript Fish
    s `shouldSatisfy` ("complete -c nihongo -f" `T.isInfixOf`)
    s `shouldSatisfy` ("--bash-completion-enriched" `T.isInfixOf`)
    s `shouldSatisfy` ("function __nihongo_complete" `T.isInfixOf`)
    s `shouldSatisfy` ("commandline -cop" `T.isInfixOf`)
