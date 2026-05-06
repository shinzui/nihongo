-- | The user-facing @nihongo kanji show <KANJI>@ subcommand. Composes
--   EP-2's KanjiVG lookup, EP-3's stroke-order parser, and EP-4's
--   inline-image rendering into a single end-to-end command. Reads the
--   kanji from a positional argument or from stdin (via
--   "Nihongo.Cli.Stdin.getTextInput"), prints a numbered narrated stroke
--   order, and (in a Kitty-graphics-capable terminal) follows it with
--   an inline image of the kanji.
module Nihongo.Cli.Commands.Kanji.Show
  ( ShowCommand (..)
  , OutputFormat (..)
  , showParser
  , runShow
  ) where

import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import Options.Applicative
  ( Parser
  , argument
  , help
  , long
  , maybeReader
  , metavar
  , option
  , optional
  , parserOptionGroup
  , showDefaultWith
  , str
  , strOption
  , switch
  , value
  )
import System.Exit (exitFailure)
import System.IO qualified as IO

import Nihongo.Cli.Stdin qualified as Stdin
import Nihongo.Kanji (Kanji, KanjiError (..), kanjiCodepointHex, mkKanji, unKanji)
import Nihongo.Kanji.KanjiVg (findStrokeSvg, resolveKanjiVgRoot)
import Nihongo.Kanji.StrokeOrder
  ( ParseError
  , Stroke (..)
  , StrokeOrderInfo (..)
  , parseStrokeOrderFile
  )
import Nihongo.Kanji.StrokeType (StrokeType (..), describeStrokeType)
import Nihongo.Prelude
import Nihongo.Pretty qualified as Pretty
import Nihongo.Terminal.Image qualified as Image

data OutputFormat
  = FormatText
  | FormatImage
  | FormatBoth
  deriving stock (Eq, Show)

data ShowCommand = ShowCommand
  { showInput :: !(Maybe Text)
  , showFormat :: !OutputFormat
  , showNoImages :: !Bool
  , showKanjivgDir :: !(Maybe FilePath)
  }
  deriving stock (Show, Eq)

showParser :: Parser ShowCommand
showParser =
  ShowCommand
    <$> optional
      ( argument
          str
          ( metavar "KANJI"
              <> help "A single Japanese character. Reads from stdin if omitted."
          )
      )
    <*> parserOptionGroup "Output options" outputGroup
    <*> parserOptionGroup "Image options" imageGroup
    <*> parserOptionGroup "Source options" sourceGroup
  where
    outputGroup =
      option
        (maybeReader parseFormat)
        ( long "format"
            <> metavar "FORMAT"
            <> value FormatBoth
            <> showDefaultWith showFormat
            <> help "Output to print: text | image | both"
        )

    showFormat FormatText = "text"
    showFormat FormatImage = "image"
    showFormat FormatBoth = "both"

    imageGroup =
      switch
        ( long "no-images"
            <> help "Do not render the inline kanji image, even when supported."
        )

    sourceGroup =
      optional
        ( strOption
            ( long "kanjivg-dir"
                <> metavar "PATH"
                <> help "Override the KanjiVG checkout directory."
            )
        )

    parseFormat "text" = Just FormatText
    parseFormat "image" = Just FormatImage
    parseFormat "both" = Just FormatBoth
    parseFormat _ = Nothing

runShow :: ShowCommand -> IO ()
runShow (ShowCommand inputArg fmt noImages dirOverride) = do
  mInput <- Stdin.getTextInput inputArg
  kanji <- case mInput of
    Nothing -> die "expected a kanji as a positional argument or on stdin"
    Just t -> readSingleKanji t
  mroot <- resolveKanjiVgRoot dirOverride
  root <- case mroot of
    Nothing -> die "could not find the KanjiVG corpus; see `nihongo help kanji-show`"
    Just r -> pure r
  mPath <- findStrokeSvg root kanji
  svg <- case mPath of
    Nothing -> die ("KanjiVG has no entry for " <> Text.singleton (unKanji kanji))
    Just p -> pure p
  result <- parseStrokeOrderFile svg
  info <- case result of
    Left err -> die ("failed to parse SVG: " <> Text.pack (show (err :: ParseError)))
    Right info -> pure info
  cap <- Image.detectImageCapabilityWithOverride noImages
  printOutput fmt cap kanji info svg

readSingleKanji :: Text -> IO Kanji
readSingleKanji raw =
  case Text.uncons (Text.strip raw) of
    Nothing -> die "expected a single character"
    Just (c, rest)
      | not (Text.null rest) -> die "expected a single character (got more)"
      | otherwise ->
          case mkKanji c of
            Left (KanjiOutOfRange ch) ->
              die ("not a Japanese character: " <> Text.singleton ch)
            Right k -> pure k

printOutput :: OutputFormat -> Image.ImageCapability -> Kanji -> StrokeOrderInfo -> FilePath -> IO ()
printOutput fmt cap kanji info svgPath = do
  case fmt of
    FormatImage -> pure ()
    _ -> do
      TIO.putStrLn (header kanji info)
      TIO.putStrLn ""
      mapM_ (TIO.putStrLn . renderStrokeLine) (strokes info)
      TIO.putStrLn ""
  case fmt of
    FormatText -> pure ()
    _ -> Image.displaySvg cap (Text.singleton (unKanji kanji)) svgPath

header :: Kanji -> StrokeOrderInfo -> Text
header k info =
  let cp = kanjiCodepointHex k
      uHex = Text.toUpper (Text.dropWhile (== '0') cp)
      glyph = Text.singleton (unKanji k)
      n = length (strokes info)
   in Pretty.bold glyph
        <> " (U+"
        <> uHex
        <> ", "
        <> Text.pack (show n)
        <> " strokes)"

renderStrokeLine :: Stroke -> Text
renderStrokeLine s =
  let n = Text.pack (show (strokeIndex s))
      d = fromMaybe "(unknown)" (describeStrokeType =<< strokeType s)
      symbol = case strokeType s of
        Just (StrokeType c _) -> "  " <> Pretty.dim (Text.singleton c)
        Nothing -> ""
   in n <> ". " <> d <> symbol

die :: Text -> IO a
die msg = do
  TIO.hPutStrLn IO.stderr msg
  exitFailure
