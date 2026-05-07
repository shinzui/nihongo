module Test.Nihongo.Cli.AliasesSpec (spec) where

import Data.Map.Strict qualified as Map
import Nihongo.Cli.Aliases (builtinCommands, expandAlias)
import Test.Hspec

spec :: Spec
spec = do
  describe "expandAlias" $ do
    it "returns [] for an empty argv" $
      expandAlias Map.empty [] `shouldBe` []

    it "leaves a flag-only argv unchanged (--version)" $
      expandAlias Map.empty ["--version"] `shouldBe` ["--version"]

    it "leaves a flag-only argv unchanged even when the flag name is in the alias map" $
      expandAlias (Map.fromList [("--help", "kanji show")]) ["--help"]
        `shouldBe` ["--help"]

    it "leaves built-in command argv unchanged" $
      expandAlias Map.empty ["kanji", "show", "漢"]
        `shouldBe` ["kanji", "show", "漢"]

    it "refuses to shadow a built-in command name with an alias" $
      expandAlias
        (Map.fromList [("kanji", "help")])
        ["kanji", "show", "漢"]
        `shouldBe` ["kanji", "show", "漢"]

    it "expands a single alias and appends remaining argv" $
      expandAlias
        (Map.fromList [("ks", "kanji show")])
        ["ks", "漢"]
        `shouldBe` ["kanji", "show", "漢"]

    it "does not recurse: alias values pass through verbatim" $
      expandAlias
        (Map.fromList [("a", "b foo"), ("b", "c bar")])
        ["a", "x"]
        `shouldBe` ["b", "foo", "x"]

    it "leaves argv unchanged when the first token is neither alias nor built-in" $
      expandAlias
        (Map.fromList [("ks", "kanji show")])
        ["unknown", "--json"]
        `shouldBe` ["unknown", "--json"]

    it "splits the expansion on whitespace via Data.Text.words" $
      expandAlias
        (Map.fromList [("multi", "  kanji   show  漢  ")])
        ["multi"]
        `shouldBe` ["kanji", "show", "漢"]

  describe "builtinCommands registry" $
    it "contains exactly the commands registered in commandParser today" $
      builtinCommands `shouldMatchList` ["hello", "help", "completions", "kanji"]
