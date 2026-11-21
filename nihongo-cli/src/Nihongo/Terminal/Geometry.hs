{-# LANGUAGE CApiFFI #-}

-- | The terminal's size in cells and in pixels, read with
--   @ioctl(TIOCGWINSZ)@ on stdout. Image layout needs the pixel size of a
--   cell to know how many columns a square image covers; @terminal-size@
--   only reports cells, so this module reads the whole @struct winsize@.
--
--   Like "Nihongo.Cli.Width", it never queries the terminal with escape
--   sequences, so it cannot hang when output is captured.
module Nihongo.Terminal.Geometry
  ( TerminalGeometry (..),
    queryGeometry,
  )
where

import Data.Word (Word16)
import Foreign.C.Types (CInt (..), CULong (..))
import Foreign.Marshal.Alloc (allocaBytes)
import Foreign.Ptr (Ptr)
import Foreign.Storable (peekElemOff)
import System.IO (hIsTerminalDevice, stdout)

data TerminalGeometry = TerminalGeometry
  { termRows :: !Int,
    termCols :: !Int,
    -- | Width of one cell in pixels.
    cellWidthPx :: !Double,
    -- | Height of one cell in pixels.
    cellHeightPx :: !Double
  }
  deriving stock (Eq, Show)

-- @capi@ rather than @ccall@: ioctl is variadic, and on aarch64-darwin
-- variadic arguments are passed differently from fixed ones, so the call
-- has to go through C with the real prototype in scope.
foreign import capi unsafe "sys/ioctl.h ioctl"
  c_ioctl :: CInt -> CULong -> Ptr Word16 -> IO CInt

foreign import capi "sys/ioctl.h value TIOCGWINSZ"
  c_TIOCGWINSZ :: CULong

-- | The geometry of the terminal stdout writes to, or 'Nothing' when
--   stdout is not a terminal or the terminal does not report its pixel
--   size (@ws_xpixel@ and @ws_ypixel@ are zero).
queryGeometry :: IO (Maybe TerminalGeometry)
queryGeometry = do
  isTty <- hIsTerminalDevice stdout
  if not isTty
    then pure Nothing
    else allocaBytes 8 $ \p -> do
      rc <- c_ioctl 1 c_TIOCGWINSZ p
      if rc /= 0
        then pure Nothing
        else do
          -- struct winsize { ws_row, ws_col, ws_xpixel, ws_ypixel }
          rows <- cell p 0
          cols <- cell p 1
          xpx <- cell p 2
          ypx <- cell p 3
          pure $
            if rows <= 0 || cols <= 0 || xpx <= 0 || ypx <= 0
              then Nothing
              else
                Just
                  TerminalGeometry
                    { termRows = rows,
                      termCols = cols,
                      cellWidthPx = fromIntegral xpx / fromIntegral cols,
                      cellHeightPx = fromIntegral ypx / fromIntegral rows
                    }
  where
    cell :: Ptr Word16 -> Int -> IO Int
    cell p i = fromIntegral <$> peekElemOff p i
