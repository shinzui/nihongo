module Main (main) where

import Test.Hspec (hspec)
import Test.Nihongo.Cli.CompletionsSpec qualified as CompletionsSpec

main :: IO ()
main = hspec CompletionsSpec.spec
