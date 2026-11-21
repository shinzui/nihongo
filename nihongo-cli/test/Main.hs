module Main (main) where

import Test.Hspec (hspec)
import Test.Nihongo.Cli.AliasesSpec qualified as AliasesSpec
import Test.Nihongo.Cli.CompletionsSpec qualified as CompletionsSpec
import Test.Nihongo.Terminal.ImageSpec qualified as ImageSpec

main :: IO ()
main = hspec $ do
  CompletionsSpec.spec
  AliasesSpec.spec
  ImageSpec.spec
