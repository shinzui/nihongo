-- | The user-facing @nihongo kanji show <KANJI>@ subcommand. Composes
--   EP-2's KanjiVG lookup, EP-3's stroke-order parser, and EP-4's
--   inline-image rendering into a single end-to-end command. Reads a
--   Japanese character or word from a positional argument or from stdin
--   (via "Nihongo.Cli.Stdin.getTextInput"), prints a numbered narrated
--   stroke order per character, and (in a Kitty-graphics-capable terminal)
--   follows each section with an inline image of the kanji.
module Nihongo.Cli.Commands.Kanji.Show
  ( ShowCommand (..),
    OutputFormat (..),
    showParser,
    runShow,
  )
where

import Data.List.NonEmpty qualified as NE
import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import Nihongo.Cli.Stdin qualified as Stdin
import Nihongo.Kanji
  ( Kanji,
    kanjiCodepointHex,
    parseKanjis,
    renderKanjiParseError,
    unKanji,
  )
import Nihongo.Kanji.KanjiVg (KanjiVgRoot, findStrokeSvg, resolveKanjiVgRoot)
import Nihongo.Kanji.StrokeOrder
  ( ParseError,
    Stroke (..),
    StrokeOrderInfo (..),
    parseStrokeOrderFile,
  )
import Nihongo.Kanji.StrokeType (StrokeType (..), describeStrokeType)
import Nihongo.Prelude
import Nihongo.Pretty qualified as Pretty
import Nihongo.Terminal.Image qualified as Image
import Options.Applicative
  ( Parser,
    argument,
    help,
    long,
    maybeReader,
    metavar,
    option,
    optional,
    parserOptionGroup,
    showDefaultWith,
    str,
    strOption,
    switch,
    value,
  )
import System.Exit (exitFailure)
import System.IO qualified as IO

data OutputFormat
  = FormatText
  | FormatImage
  | FormatBoth
  deriving stock (Eq, Show)

data ShowCommand = ShowCommand
  { showInput :: !(Maybe Text),
    showFormat :: !OutputFormat,
    showNoImages :: !Bool,
    showKanjivgDir :: !(Maybe FilePath)
  }
  deriving stock (Show, Eq)

showParser :: Parser ShowCommand
showParser =
  ShowCommand
    <$> optional
      ( argument
          str
          ( metavar "KANJI"
              <> help "A Japanese character or word. Reads from stdin if omitted."
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
  raw <- case mInput of
    Nothing -> die "expected a Japanese word as a positional argument or on stdin"
    Just t -> pure t
  kanjis <- case parseKanjis raw of
    Left e -> die (renderKanjiParseError e)
    Right ks -> pure ks
  mroot <- resolveKanjiVgRoot dirOverride
  root <- case mroot of
    Nothing -> die "could not find the KanjiVG corpus; see `nihongo help kanji-show`"
    Just r -> pure r
  cap <- Image.detectImageCapabilityWithOverride noImages
  let numbered = NE.zip (1 NE.:| [2 ..]) kanjis
  results <- traverse (renderOne fmt cap root) (NE.toList numbered)
  unless (or results) exitFailure

-- | Render one character's section. Returns 'True' on success, 'False'
--   when the SVG was missing or failed to parse (in which case a
--   placeholder body is printed). The caller uses these flags to decide
--   the exit code: any 'True' means partial success and exit 0.
renderOne ::
  OutputFormat ->
  Image.ImageCapability ->
  KanjiVgRoot ->
  (Int, Kanji) ->
  IO Bool
renderOne fmt cap root (idx, kanji) = do
  when (idx > 1) (TIO.putStrLn "")
  mPath <- findStrokeSvg root kanji
  case mPath of
    Nothing -> do
      renderMissingHeader kanji
      pure False
    Just svg -> do
      result <- parseStrokeOrderFile svg
      case result of
        Left err -> do
          TIO.hPutStrLn
            IO.stderr
            ( "warning: failed to parse SVG for "
                <> Text.singleton (unKanji kanji)
                <> ": "
                <> Text.pack (show (err :: ParseError))
            )
          renderMissingHeader kanji
          pure False
        Right info -> do
          printOutput fmt cap kanji info svg
          pure True

renderMissingHeader :: Kanji -> IO ()
renderMissingHeader kanji = do
  TIO.putStrLn (missingHeader kanji)
  TIO.putStrLn "(no KanjiVG entry)"

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
  let n = length (strokes info)
      strokeCount = Text.pack (show n) <> " strokes"
   in headerWith k strokeCount

missingHeader :: Kanji -> Text
missingHeader k = headerWith k "? strokes"

headerWith :: Kanji -> Text -> Text
headerWith k strokeCount =
  let cp = kanjiCodepointHex k
      uHex = Text.toUpper (Text.dropWhile (== '0') cp)
      glyph = Text.singleton (unKanji k)
   in Pretty.bold glyph
        <> " (U+"
        <> uHex
        <> ", "
        <> strokeCount
        <> ")"

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
