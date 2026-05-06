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
  ) where

import Control.Exception (IOException, try)
import Control.Monad (replicateM_)
import Data.ByteString (ByteString)
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as BS8
import Data.Text qualified as Text
import System.Environment (lookupEnv)
import System.IO qualified as IO
import System.Process (readProcess)

import Nihongo.Prelude

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
