module Main (main) where

import Test.Hspec (hspec)
import Test.Nihongo.Cli.AliasesSpec qualified as AliasesSpec
import Test.Nihongo.Cli.CompletionsSpec qualified as CompletionsSpec

main :: IO ()
main = hspec $ do
  CompletionsSpec.spec
  AliasesSpec.spec
