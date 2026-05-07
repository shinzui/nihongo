module Test.Nihongo.Cli.AliasesSpec (spec) where

import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Nihongo.Cli (runCliParserInfo)
import Nihongo.Cli.Alias (renderAliasTable)
import Nihongo.Cli.Aliases (builtinCommands, expandAlias)
import Nihongo.Cli.Help (helpTopics)
import Nihongo.Prelude
import Options.Applicative (ParserResult (..), defaultPrefs, execParserPure)
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

  describe "builtinCommands registry" $ do
    it "contains exactly the commands registered in commandParser today" $
      builtinCommands
        `shouldMatchList` ["hello", "help", "completions", "kanji", "alias"]

    it "the parser accepts every name in builtinCommands" $
      mapM_
        ( \name ->
            case execParserPure defaultPrefs runCliParserInfo [T.unpack name, "--help"] of
              Failure _ -> pure ()
              Success _ -> expectationFailure (T.unpack name <> " --help unexpectedly succeeded")
              CompletionInvoked _ -> expectationFailure (T.unpack name <> " --help triggered completion path")
        )
        builtinCommands

    it "the parser refuses an unknown top-level command" $
      case execParserPure defaultPrefs runCliParserInfo ["definitely-not-real"] of
        Failure _ -> pure ()
        _ -> expectationFailure "expected Failure for unknown subcommand"

  describe "renderAliasTable" $ do
    it "prints a friendly note for an empty map" $
      renderAliasTable Map.empty `shouldBe` "No aliases configured.\n"

    it "renders a single entry without padding" $
      renderAliasTable (Map.singleton "ks" "kanji show")
        `shouldBe` "ks = kanji show\n"

    it "left-pads the longest name and aligns the '=' separators" $
      renderAliasTable
        ( Map.fromList
            [ ("h", "help"),
              ("kp", "kanji png"),
              ("ks", "kanji show")
            ]
        )
        `shouldBe` T.unlines
          [ "h  = help",
            "kp = kanji png",
            "ks = kanji show"
          ]

    it "sorts entries ascending by alias name" $
      renderAliasTable
        ( Map.fromList
            [ ("zz", "zulu"),
              ("aa", "alpha")
            ]
        )
        `shouldBe` T.unlines
          [ "aa = alpha",
            "zz = zulu"
          ]

  describe "nihongo help aliases" $ do
    it "is registered in the help topic index" $
      case find ((== "aliases") . (^. #topicName)) helpTopics of
        Nothing -> expectationFailure "aliases topic not registered"
        Just _ -> pure ()

    it "topic body covers schema, precedence, built-in protection, and listing" $
      case find ((== "aliases") . (^. #topicName)) helpTopics of
        Nothing -> expectationFailure "aliases topic not registered"
        Just t -> do
          ("SCHEMA" `T.isInfixOf` (t ^. #topicContent)) `shouldBe` True
          ("PRECEDENCE" `T.isInfixOf` (t ^. #topicContent)) `shouldBe` True
          ("BUILT-IN PROTECTION" `T.isInfixOf` (t ^. #topicContent)) `shouldBe` True
          ("nihongo alias list" `T.isInfixOf` (t ^. #topicContent)) `shouldBe` True
