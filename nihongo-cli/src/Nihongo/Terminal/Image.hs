-- | Terminal-side image rendering for nihongo. Capability detection
--   identifies Kitty-graphics-capable terminals (Kitty, WezTerm, Ghostty)
--   directly via env vars, and via @tmux show-environment@ when running
--   inside tmux. Subsequent milestones add the Kitty emitter, the SVG →
--   PNG rasterisation step, and the high-level @displaySvg@ orchestrator.
module Nihongo.Terminal.Image
  ( ImageCapability (..)
  , detectImageCapability
  , detectImageCapabilityWithOverride
  ) where

import Control.Exception (IOException, try)
import Data.Text qualified as Text
import System.Environment (lookupEnv)
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
