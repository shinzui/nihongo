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
    displaySvgBeside,
    displaySvgRow,
    SideLayout (..),
    sideLayout,
    RowLayout (..),
    rowLayout,
    Placement (..),
    buildKittyStream,
  )
where

import Control.Exception (IOException, try)
import Control.Monad (replicateM_)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as BS8
import Data.Foldable (for_)
import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import Data.Traversable (for)
import Nihongo.Prelude
import Nihongo.Pretty qualified as Pretty
import Nihongo.Terminal.Geometry (TerminalGeometry (..), queryGeometry)
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
  let kittyStream = encodeKitty stacked pngBytes
      bytes =
        if isInTmux
          then BS8.pack "\ESCPtmux;" <> tmuxDouble kittyStream <> BS8.pack "\ESC\\"
          else kittyStream
  BS8.hPut IO.stdout bytes
  replicateM_ imageRows (BS8.hPut IO.stdout "\n")
  IO.hFlush IO.stdout
  where
    stacked = Placement {placeRows = imageRows, placeCols = Nothing, holdCursor = False}

-- | Where and how big the terminal draws an image, in cells.
data Placement = Placement
  { -- | Rows the image covers (Kitty's @r@).
    placeRows :: !Int,
    -- | Columns the image covers (Kitty's @c@). Without it the terminal
    --   picks the width that keeps the image's aspect ratio.
    placeCols :: !(Maybe Int),
    -- | Leave the cursor where it was (Kitty's @C=1@) instead of moving
    --   it past the image, so text can be written beside the image.
    holdCursor :: !Bool
  }
  deriving stock (Eq, Show)

encodeKitty :: Placement -> ByteString -> ByteString
encodeKitty placement pngBytes =
  buildKittyStream placement (splitChunks chunkSize (Base64.encode pngBytes))

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
--   escapes. The first carries @a=T,f=100,t=d@ and the placement keys;
--   each subsequent chunk carries only @m=1@; the last chunk in the
--   stream carries @m=0@. A single-chunk stream collapses to one @m=0@
--   APC.
buildKittyStream :: Placement -> [ByteString] -> ByteString
buildKittyStream _ [] = ""
buildKittyStream placement [c] = buildFirstEscape placement False c
buildKittyStream placement (c0 : rest) =
  buildFirstEscape placement True c0 <> buildRest rest
  where
    buildRest [] = ""
    buildRest [c] = buildContEscape False c
    buildRest (c : cs) = buildContEscape True c <> buildRest cs

-- | First chunk carries the action, format, transmission and placement
--   keys.
buildFirstEscape :: Placement -> Bool -> ByteString -> ByteString
buildFirstEscape placement moreComing chunk =
  "\ESC_Ga=T,f=100,t=d,r="
    <> BS8.pack (show (placeRows placement))
    <> maybe "" (\c -> ",c=" <> BS8.pack (show c)) (placeCols placement)
    <> (if holdCursor placement then ",C=1" else "")
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

-- | Show the image with @textLines@ printed to its right, so a numbered
--   stroke list sits beside the numbered strokes it describes instead of
--   above them. Falls back to the stacked layout (the lines, a blank line,
--   then 'displaySvg') whenever the side-by-side one cannot be drawn
--   reliably: no image support, inside tmux (where the outer terminal's
--   cursor need not match ours), a terminal that does not report its
--   pixel size, or one too small for both columns.
displaySvgBeside :: ImageCapability -> Text -> FilePath -> [Text] -> IO ()
displaySvgBeside cap label svgPath textLines = do
  mLayout <- (>>= \g -> sideLayout g (length textLines)) <$> placementGeometry cap
  case mLayout of
    Nothing -> stackedLayout
    Just layout -> do
      ensured <- ensurePng svgPath
      case ensured of
        Left err -> do
          TIO.hPutStrLn IO.stderr ("warning: " <> err)
          mapM_ TIO.putStrLn textLines
          TIO.putStrLn ""
          TIO.putStrLn (Pretty.dim ("[Image: " <> label <> "]"))
        Right png -> drawBeside layout png textLines
  where
    stackedLayout = do
      mapM_ TIO.putStrLn textLines
      TIO.putStrLn ""
      displaySvg cap label svgPath

-- | Show a word's images in a row, left to right, wrapping onto further
--   rows when the terminal is too narrow for all of them. Falls back to
--   stacking them, separated by blank lines, under the same conditions as
--   'displaySvgBeside'. An image that cannot be rasterised prints its
--   warning and placeholder before the row.
displaySvgRow :: ImageCapability -> [(Text, FilePath)] -> IO ()
displaySvgRow _ [] = pure ()
displaySvgRow cap images = do
  mLayout <- (>>= \g -> rowLayout g (length images)) <$> placementGeometry cap
  case mLayout of
    Nothing -> stackedLayout
    Just layout -> do
      pngs <- fmap concat . for images $ \(label, svgPath) -> do
        ensured <- ensurePng svgPath
        case ensured of
          Left err -> do
            TIO.hPutStrLn IO.stderr ("warning: " <> err)
            TIO.putStrLn (Pretty.dim ("[Image: " <> label <> "]"))
            pure []
          Right png -> pure [png]
      drawRows layout pngs
  where
    stackedLayout =
      for_ (zip [0 :: Int ..] images) $ \(i, (label, svgPath)) -> do
        when (i > 0) (TIO.putStrLn "")
        displaySvg cap label svgPath

-- | The terminal's geometry when images can be placed beside other
--   cells: Kitty graphics, outside tmux (where the outer terminal's
--   cursor need not match ours), and a terminal that reports its pixel
--   size.
placementGeometry :: ImageCapability -> IO (Maybe TerminalGeometry)
placementGeometry NoImageSupport = pure Nothing
placementGeometry KittyGraphics = do
  inTmux <- isJust <$> lookupEnv "TMUX"
  if inTmux then pure Nothing else queryGeometry

-- | Rows and columns a square image covers: 'imageRows' tall, shrunk to
--   leave two rows of a short terminal free, and as wide as the cell's
--   pixel aspect ratio makes it. 'Nothing' when it would be too small to
--   read.
imageFootprint :: TerminalGeometry -> Maybe (Int, Int)
imageFootprint g
  | rows < minImageRows = Nothing
  | otherwise = Just (rows, squareCols g rows)
  where
    rows = min imageRows (termRows g - 2)

-- | Columns a square image @rows@ tall covers.
squareCols :: TerminalGeometry -> Int -> Int
squareCols g rows = ceiling (fromIntegral rows * cellHeightPx g / cellWidthPx g)

-- | The smallest a row's images shrink to so a word fits on one line.
--   Smaller than this, the stroke numbers get hard to read, so the row
--   wraps at full size instead.
minRowFitRows :: Int
minRowFitRows = 12

-- | How a row of images is laid out: each image's footprint, the columns
--   from one image's left edge to the next, and how many fit on a line.
data RowLayout = RowLayout
  { rowImageRows :: !Int,
    rowImageCols :: !Int,
    rowStride :: !Int,
    rowPerLine :: !Int
  }
  deriving stock (Eq, Show)

-- | Lay out @n@ images. When they do not all fit on one line at full
--   size, shrink them until they do, but no smaller than
--   'minRowFitRows'; past that, keep full size and wrap.
rowLayout :: TerminalGeometry -> Int -> Maybe RowLayout
rowLayout g n = do
  full@(_, fullCols) <- imageFootprint g
  guard (fullCols <= termCols g)
  let count = max 1 n
      fitsOnOneLine c = count * c + sideGap * (count - 1) <= termCols g
      colsEach = (termCols g - sideGap * (count - 1)) `div` count
      rowsFit = floor (fromIntegral colsEach * cellWidthPx g / cellHeightPx g)
      (rows, cols)
        | fitsOnOneLine fullCols = full
        | rowsFit >= minRowFitRows = (rowsFit, squareCols g rowsFit)
        | otherwise = full
      stride = cols + sideGap
  pure
    RowLayout
      { rowImageRows = rows,
        rowImageCols = cols,
        rowStride = stride,
        rowPerLine = max 1 ((termCols g + sideGap) `div` stride)
      }

-- | Draw the images 'rowPerLine' to a line, with a blank line between
--   lines. Each line reserves its rows first, as 'drawBeside' does, then
--   places every image at its column without moving the cursor.
drawRows :: RowLayout -> [FilePath] -> IO ()
drawRows layout pngs =
  for_ (zip [0 :: Int ..] (chunksOf (rowPerLine layout) pngs)) $ \(i, line) -> do
    when (i > 0) (BS8.hPut IO.stdout "\n")
    let rows = rowImageRows layout
        placement =
          Placement
            { placeRows = rows,
              placeCols = Just (rowImageCols layout),
              holdCursor = True
            }
    replicateM_ rows (BS8.hPut IO.stdout "\n")
    BS8.hPut IO.stdout ("\ESC[" <> BS8.pack (show rows) <> "A")
    for_ (zip [0 :: Int ..] line) $ \(j, png) -> do
      pngBytes <- BS.readFile png
      let column = j * rowStride layout
      BS8.hPut IO.stdout "\r"
      when (column > 0) (BS8.hPut IO.stdout ("\ESC[" <> BS8.pack (show column) <> "C"))
      BS8.hPut IO.stdout (encodeKitty placement pngBytes)
    replicateM_ rows (BS8.hPut IO.stdout "\n")
    IO.hFlush IO.stdout
  where
    chunksOf n xs = case splitAt n xs of
      (h, []) -> [h]
      (h, t) -> h : chunksOf n t

-- | The cell footprint of a side-by-side block: the image's rows and
--   columns, and the column the text starts at.
data SideLayout = SideLayout
  { sideImageRows :: !Int,
    sideImageCols :: !Int,
    sideTextCol :: !Int,
    -- | Rows the whole block covers: the taller of the image and the text.
    sideBlockRows :: !Int
  }
  deriving stock (Eq, Show)

-- | Columns between the image and the text.
sideGap :: Int
sideGap = 2

-- | Narrowest text column worth drawing beside the image. The longest
--   stroke line (e.g. @26. curve-up-hook  ㇟@) is about 22 columns.
minTextCols :: Int
minTextCols = 24

-- | Below this many rows the stroke numbers in the image are unreadable,
--   so the stacked layout is used instead.
minImageRows :: Int
minImageRows = 8

-- | Fit an image and @nLines@ lines of text side by side in the terminal.
--   The image is square, so its column count follows from the cell's
--   pixel aspect ratio. The block must fit on screen without scrolling,
--   because 'drawBeside' moves the cursor back up over it.
sideLayout :: TerminalGeometry -> Int -> Maybe SideLayout
sideLayout g nLines = do
  (rows, cols) <- imageFootprint g
  let textCol = cols + sideGap
      block = max rows nLines
  guard (block < termRows g)
  guard (textCol + minTextCols <= termCols g)
  pure
    SideLayout
      { sideImageRows = rows,
        sideImageCols = cols,
        sideTextCol = textCol,
        sideBlockRows = block
      }

-- | Draw the block. First print 'sideBlockRows' newlines and move back
--   up, so any scrolling happens before drawing and the image and text
--   stay aligned. Then place the image without moving the cursor, write
--   each text line shifted right past it, and finish on the row below
--   the block.
drawBeside :: SideLayout -> FilePath -> [Text] -> IO ()
drawBeside layout png textLines = do
  pngBytes <- BS.readFile png
  let block = sideBlockRows layout
      placement =
        Placement
          { placeRows = sideImageRows layout,
            placeCols = Just (sideImageCols layout),
            holdCursor = True
          }
      shift = "\ESC[" <> Text.pack (show (sideTextCol layout)) <> "C"
  replicateM_ block (BS8.hPut IO.stdout "\n")
  BS8.hPut IO.stdout ("\ESC[" <> BS8.pack (show block) <> "A\r")
  BS8.hPut IO.stdout (encodeKitty placement pngBytes)
  IO.hFlush IO.stdout
  mapM_ (\l -> TIO.putStrLn (shift <> l)) textLines
  replicateM_ (block - length textLines) (TIO.putStrLn "")
  IO.hFlush IO.stdout

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
