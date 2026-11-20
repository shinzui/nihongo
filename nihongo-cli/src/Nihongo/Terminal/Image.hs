-- | Terminal-side image rendering for nihongo. Capability detection
--   identifies Kitty-graphics-capable terminals (Kitty, WezTerm, Ghostty, Rex)
--   directly via env vars, and via @tmux show-environment@ when running
--   inside tmux. Subsequent milestones add the Kitty emitter, the SVG →
--   PNG rasterisation step, and the high-level @displaySvg@ orchestrator.
module Nihongo.Terminal.Image
  ( ImageCapability (..),
    detectImageCapability,
    detectImageCapabilityWithOverride,
    displayImage,
    ensurePng,
    displaySvg,
  )
where

import Control.Exception (IOException, try)
import Control.Monad (replicateM_)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as BS8
import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import Nihongo.Prelude
import Nihongo.Pretty qualified as Pretty
import System.Directory (createDirectoryIfMissing, doesFileExist, getHomeDirectory)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath qualified as FP
import System.IO qualified as IO
import System.Process (readProcess, readProcessWithExitCode)
import Text.Printf (printf)

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
          || mProg == Just "rex"
          || mTerm == Just "xterm-rex"
  if directHit
    then pure KittyGraphics
    else case mTmux of
      Nothing -> pure NoImageSupport
      Just _ -> do
        outerProg <- tmuxShowEnv "TERM_PROGRAM"
        pure $
          if outerProg `elem` [Just "WezTerm", Just "ghostty", Just "kitty", Just "rex"]
            then KittyGraphics
            else NoImageSupport

-- | Number of terminal rows the rendered image will occupy. Tuned for
--   stroke-order images — taller than kizamu's 8-row default to make
--   detail readable.
imageRows :: Int
imageRows = 20

-- | Maximum size, in bytes of base64-encoded payload, of a single Kitty
--   APC chunk. The Kitty graphics protocol caps each chunk; PNGs larger
--   than this get split across multiple @m=1@ continuation chunks ending
--   with @m=0@.
chunkSize :: Int
chunkSize = 4096

-- | Display a PNG file at an absolute path using the Kitty graphics
--   protocol with @t=d@ (inline base64 transmission). We do not use
--   @t=f@ (file path) because WezTerm's tmux passthrough silently
--   drops file-path Kitty escapes in some recent builds.
--
--   The PNG payload is split into 4096-byte base64 chunks (the per-APC
--   limit Kitty's protocol specifies). Outside tmux, each chunk is
--   emitted as its own @\\e_G...\\e\\\\@ sequence. Inside tmux, all
--   chunks are concatenated and emitted inside a *single* outer tmux
--   DCS passthrough envelope (rather than one envelope per chunk) —
--   WezTerm's tmux passthrough buffers chunk continuations within a
--   single DCS event, but does not associate continuations across
--   separate DCS events.
--
--   After emitting all chunks, prints @imageRows@ newlines so the
--   cursor lands below the rendered image, and flushes stdout.
displayImage :: FilePath -> IO ()
displayImage absPath = do
  isInTmux <- maybe False (const True) <$> lookupEnv "TMUX"
  pngBytes <- BS.readFile absPath
  let allBase64 = Base64.encode pngBytes
      chunks = splitChunks chunkSize allBase64
      kittyStream = buildKittyStream chunks
      bytes =
        if isInTmux
          then BS8.pack "\ESCPtmux;" <> tmuxDouble kittyStream <> BS8.pack "\ESC\\"
          else kittyStream
  BS8.hPut IO.stdout bytes
  replicateM_ imageRows (BS8.hPut IO.stdout "\n")
  IO.hFlush IO.stdout

-- | Split a ByteString into chunks of at most @n@ bytes each. The last
--   chunk may be shorter; an empty input yields no chunks.
splitChunks :: Int -> ByteString -> [ByteString]
splitChunks n bs
  | BS.null bs = []
  | BS.length bs <= n = [bs]
  | otherwise =
      let (h, t) = BS.splitAt n bs
       in h : splitChunks n t

-- | Concatenate a list of base64 chunks into a sequence of Kitty APC
--   escapes. The first carries @a=T,f=100,t=d,r=<rows>@; each subsequent
--   chunk carries only @m=1@; the last chunk in the stream carries
--   @m=0@. A single-chunk stream collapses to one @m=0@ APC.
buildKittyStream :: [ByteString] -> ByteString
buildKittyStream [] = ""
buildKittyStream [only] = buildFirstEscape False only
buildKittyStream (c0 : rest) =
  buildFirstEscape True c0 <> buildRest rest
  where
    buildRest [] = ""
    buildRest [c] = buildContEscape False c
    buildRest (c : cs) = buildContEscape True c <> buildRest cs

-- | First chunk carries the action+format+rows+transmission keys.
buildFirstEscape :: Bool -> ByteString -> ByteString
buildFirstEscape moreComing chunk =
  "\ESC_Ga=T,f=100,t=d,r="
    <> BS8.pack (show imageRows)
    <> (if moreComing then ",m=1" else ",m=0")
    <> ";"
    <> chunk
    <> "\ESC\\"

-- | Continuation chunks carry only the @m=@ key.
buildContEscape :: Bool -> ByteString -> ByteString
buildContEscape moreComing chunk =
  "\ESC_Gm=" <> (if moreComing then "1" else "0") <> ";" <> chunk <> "\ESC\\"

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

-- | Bumped whenever the rasterisation arguments change so that old
--   cache entries (rendered with different parameters) are naturally
--   bypassed without manual cleanup. Mixed into the SHA-256 cache key.
cacheVersion :: ByteString
cacheVersion = "v2:width=384"

-- | Pixel width passed to @rsvg-convert --width@. The KanjiVG SVGs are
--   only 109 px native; rendering at this larger size gives the inline
--   image enough resolution to remain crisp at @r=20@ rows of terminal
--   display.
rasteriseWidthPx :: Int
rasteriseWidthPx = 384

-- | Given an SVG file path, return the path to a cached PNG of it. If
--   the PNG does not exist yet (cache miss), rasterise it via
--   @rsvg-convert@. The cache key is the SHA-256 of @cacheVersion@
--   prepended to the SVG file contents — so changing @cacheVersion@
--   invalidates every entry in lockstep with the rasterisation params.
ensurePng :: FilePath -> IO (Either Text FilePath)
ensurePng svgPath = do
  svgBytes <- BS.readFile svgPath
  let digest = SHA256.hash (cacheVersion <> svgBytes)
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
          [ "--format=png",
            "--width",
            show rasteriseWidthPx,
            "--keep-aspect-ratio",
            "--output",
            pngPath,
            svgPath
          ]
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
