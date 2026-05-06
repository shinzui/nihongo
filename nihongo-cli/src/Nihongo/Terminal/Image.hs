-- | Terminal-side image rendering for nihongo. Capability detection
--   identifies Kitty-graphics-capable terminals (Kitty, WezTerm, Ghostty)
--   directly via env vars, and via @tmux show-environment@ when running
--   inside tmux. Subsequent milestones add the Kitty emitter, the SVG →
--   PNG rasterisation step, and the high-level @displaySvg@ orchestrator.
module Nihongo.Terminal.Image
  ( ImageCapability (..)
  , detectImageCapability
  , detectImageCapabilityWithOverride
  , displayImage
  , ensurePng
  , displaySvg
  ) where

import Control.Exception (IOException, try)
import Control.Monad (replicateM_)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as BS8
import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import System.Directory (createDirectoryIfMissing, doesFileExist, getHomeDirectory)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath qualified as FP
import System.IO qualified as IO
import System.Process (readProcess, readProcessWithExitCode)
import Text.Printf (printf)

import Nihongo.Prelude
import Nihongo.Pretty qualified as Pretty

data ImageCapability
  = KittyGraphics
  | NoImageSupport
  deriving stock (Eq, Show)

-- | Decide whether the current terminal supports Kitty graphics. The
--   first argument is the user-supplied @--no-images@ flag — when 'True',
--   short-circuit to 'NoImageSupport' regardless of the environment.
detectImageCapabilityWithOverride :: Bool -> IO ImageCapability
detectImageCapabilityWithOverride True = pure NoImageSupport
detectImageCapabilityWithOverride False = detectImageCapability

detectImageCapability :: IO ImageCapability
detectImageCapability = do
  mKitty <- lookupEnv "KITTY_WINDOW_ID"
  mTerm <- lookupEnv "TERM"
  mProg <- lookupEnv "TERM_PROGRAM"
  mTmux <- lookupEnv "TMUX"
  let directHit =
        isJust mKitty
          || mTerm == Just "xterm-kitty"
          || mProg == Just "WezTerm"
          || mProg == Just "ghostty"
  if directHit
    then pure KittyGraphics
    else case mTmux of
      Nothing -> pure NoImageSupport
      Just _ -> do
        outerProg <- tmuxShowEnv "TERM_PROGRAM"
        pure $
          if outerProg `elem` [Just "WezTerm", Just "ghostty", Just "kitty"]
            then KittyGraphics
            else NoImageSupport

-- | Number of terminal rows the rendered image will occupy. Tuned for
--   stroke-order images — taller than kizamu's 8-row default to make
--   detail readable.
imageRows :: Int
imageRows = 12

-- | Display a PNG file at an absolute path using the Kitty graphics
--   protocol. The terminal reads the file itself (@t=f@) so we do not
--   stream bytes through stdout. When @TMUX@ is set, wraps the inner
--   escape in tmux's DCS passthrough envelope.
--
--   After emitting the escape, prints @imageRows@ newlines so the cursor
--   lands below the rendered image, and flushes stdout.
displayImage :: FilePath -> IO ()
displayImage absPath = do
  isInTmux <- maybe False (const True) <$> lookupEnv "TMUX"
  let payload = Base64.encode (BS8.pack absPath)
      inner =
        "\ESC_Ga=T,f=100,t=f,r="
          <> BS8.pack (show imageRows)
          <> ";"
          <> payload
          <> "\ESC\\"
      escaped =
        if isInTmux
          then BS8.pack "\ESCPtmux;" <> tmuxDouble inner <> BS8.pack "\ESC\\"
          else inner
  BS8.hPut IO.stdout escaped
  replicateM_ imageRows (BS8.hPut IO.stdout "\n")
  IO.hFlush IO.stdout

-- | Double every ESC byte to escape it through tmux's DCS passthrough.
tmuxDouble :: ByteString -> ByteString
tmuxDouble =
  BS8.concatMap (\c -> if c == '\ESC' then "\ESC\ESC" else BS8.singleton c)

-- | Resolve @<XDG_CACHE_HOME or ~/.cache>/nihongo/strokes/@ and ensure
--   the directory exists. Returns the absolute path.
cacheDir :: IO FilePath
cacheDir = do
  mXdg <- lookupEnv "XDG_CACHE_HOME"
  home <- getHomeDirectory
  let root = case mXdg of
        Just p | not (null p) -> p
        _ -> home FP.</> ".cache"
      dir = root FP.</> "nihongo" FP.</> "strokes"
  createDirectoryIfMissing True dir
  pure dir

-- | Given an SVG file path, return the path to a cached PNG of it. If the
--   PNG does not exist yet (cache miss), rasterise it via @rsvg-convert@.
--   The cache key is the SHA-256 of the SVG file contents.
ensurePng :: FilePath -> IO (Either Text FilePath)
ensurePng svgPath = do
  svgBytes <- BS.readFile svgPath
  let digest = SHA256.hash svgBytes
      hex = Text.pack (concatMap (printf "%02x") (BS.unpack digest))
  dir <- cacheDir
  let pngPath = dir FP.</> Text.unpack hex FP.<.> "png"
  cached <- doesFileExist pngPath
  if cached
    then pure (Right pngPath)
    else rasterise svgPath pngPath

rasterise :: FilePath -> FilePath -> IO (Either Text FilePath)
rasterise svgPath pngPath = do
  result <-
    try
      ( readProcessWithExitCode
          "rsvg-convert"
          ["--format=png", "--output", pngPath, svgPath]
          ""
      ) ::
      IO (Either IOException (ExitCode, String, String))
  case result of
    Left e -> pure (Left ("rsvg-convert not found: " <> Text.pack (show e)))
    Right (ExitSuccess, _, _) -> pure (Right pngPath)
    Right (ExitFailure n, _, e) ->
      pure (Left ("rsvg-convert exit " <> Text.pack (show n) <> ": " <> Text.pack e))

-- | High-level entry point. Given a capability decision, a label (used
--   for the fallback placeholder), and an SVG file path, do the right
--   thing: under 'KittyGraphics', rasterise + display; otherwise print
--   a dim @[Image: <label>]@ placeholder. Rasterisation failures (e.g.
--   @rsvg-convert@ missing on @PATH@) print a stderr warning and fall
--   back to the placeholder rather than aborting the program.
displaySvg :: ImageCapability -> Text -> FilePath -> IO ()
displaySvg NoImageSupport label _ =
  TIO.putStrLn (Pretty.dim ("[Image: " <> label <> "]"))
displaySvg KittyGraphics label svgPath = do
  ensured <- ensurePng svgPath
  case ensured of
    Left err -> do
      TIO.hPutStrLn IO.stderr ("warning: " <> err)
      TIO.putStrLn (Pretty.dim ("[Image: " <> label <> "]"))
    Right png -> displayImage png

-- | Run @tmux show-environment -g <var>@ and pull the value out. Swallows
--   any 'IOException' (so callers still work if @tmux@ is missing or the
--   var is unset).
tmuxShowEnv :: Text -> IO (Maybe Text)
tmuxShowEnv var = do
  result <-
    try
      ( readProcess
          "tmux"
          ["show-environment", "-g", Text.unpack var]
          ""
      ) ::
      IO (Either IOException String)
  pure $ case result of
    Left _ -> Nothing
    Right out -> parseLine out
  where
    prefix = var <> "="
    parseLine s =
      case dropWhile (not . Text.isPrefixOf prefix) (Text.lines (Text.pack s)) of
        (l : _) -> Just (Text.drop (Text.length prefix) l)
        [] -> Nothing
