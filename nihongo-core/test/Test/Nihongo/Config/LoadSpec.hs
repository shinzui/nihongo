module Test.Nihongo.Config.LoadSpec (spec) where

import Data.Map.Strict qualified as Map
import Nihongo.Config.Load (decodeNihongoConfig, resolveAliases)
import Test.Hspec

spec :: Spec
spec = describe "decodeNihongoConfig" $ do
  it "treats an empty document as no aliases" $
    case decodeNihongoConfig "" of
      Right cfg -> resolveAliases cfg `shouldBe` Map.empty
      Left e -> expectationFailure (show e)

  it "decodes a single aliases block with one entry" $
    case decodeNihongoConfig "aliases { ks \"kanji show\" }" of
      Right cfg ->
        resolveAliases cfg `shouldBe` Map.fromList [("ks", "kanji show")]
      Left e -> expectationFailure (show e)

  it "collapses within-file duplicates to the last occurrence" $
    case decodeNihongoConfig
      "aliases {\n  ks \"first\"\n  ks \"second\"\n}" of
      Right cfg ->
        Map.lookup "ks" (resolveAliases cfg) `shouldBe` Just "second"
      Left e -> expectationFailure (show e)
