module Main (main) where

import Test.Hspec (hspec)
import Test.Nihongo.Kanji.StrokeOrderSpec qualified as StrokeOrderSpec

main :: IO ()
main = hspec StrokeOrderSpec.spec
