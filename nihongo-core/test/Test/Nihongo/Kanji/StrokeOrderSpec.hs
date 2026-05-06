{-# OPTIONS_GHC -Wno-x-partial #-}

module Test.Nihongo.Kanji.StrokeOrderSpec (spec) where

import Data.Text.IO qualified as TIO
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

import Nihongo.Kanji.StrokeOrder
import Nihongo.Kanji.StrokeType (StrokeType (..))

spec :: Spec
spec = describe "Nihongo.Kanji.StrokeOrder" $ do
  describe "漢 (06f22.svg)" $ do
    it "has 13 strokes in numeric order" $ do
      info <- loadFixture "06f22.svg"
      map strokeIndex (strokes info) `shouldBe` [1 .. 13]

    it "first stroke is dot ㇔" $ do
      info <- loadFixture "06f22.svg"
      let s1 = head (strokes info)
      baseChar <$> strokeType s1 `shouldBe` Just '\x31D4'

    it "captures variant suffix on stroke 5 (㇑a)" $ do
      info <- loadFixture "06f22.svg"
      let s5 = strokes info !! 4
      variant <$> strokeType s5 `shouldBe` Just (Just "a")

    it "exposes 漢 at the root component" $ do
      info <- loadFixture "06f22.svg"
      compElement (rootComponent (componentTree info)) `shouldBe` Just "漢"

  describe "あ (03042.svg)" $ do
    it "has 3 strokes" $ do
      info <- loadFixture "03042.svg"
      length (strokes info) `shouldBe` 3

    it "exposes あ at the root component" $ do
      info <- loadFixture "03042.svg"
      compElement (rootComponent (componentTree info)) `shouldBe` Just "あ"

  describe "一 (04e00.svg)" $ do
    it "has 1 horizontal stroke" $ do
      info <- loadFixture "04e00.svg"
      length (strokes info) `shouldBe` 1
      baseChar <$> strokeType (head (strokes info))
        `shouldBe` Just '\x31D0'

  describe "error reporting" $ do
    it "rejects empty input" $ do
      parseStrokeOrderText "" `shouldSatisfy` isLeft

loadFixture :: FilePath -> IO StrokeOrderInfo
loadFixture name = do
  txt <- TIO.readFile ("test/fixtures/" <> name)
  case parseStrokeOrderText txt of
    Right info -> pure info
    Left err -> error (show err)

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False
