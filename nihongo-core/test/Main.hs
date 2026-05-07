module Main (main) where

import Test.Hspec (hspec)
import Test.Nihongo.Config.LoadSpec qualified as LoadSpec
import Test.Nihongo.Kanji.StrokeOrderSpec qualified as StrokeOrderSpec

main :: IO ()
main = hspec $ do
  StrokeOrderSpec.spec
  LoadSpec.spec
