-- | Resolve a 'Kanji' to the absolute filesystem path of a cached PNG
--   rendered from its KanjiVG SVG. Composes the existing KanjiVG lookup
--   ('Nihongo.Kanji.KanjiVg.resolveKanjiVgRoot' /
--   'Nihongo.Kanji.KanjiVg.findStrokeSvg') with the SVG → PNG cache
--   ('Nihongo.Terminal.Image.ensurePng'). The PNG cache is shared with the
--   inline-image renderer used by @nihongo kanji show@, so consumers
--   benefit from cross-command cache hits.
module Nihongo.Kanji.Png
  ( KanjiPngOptions (..),
    defaultKanjiPngOptions,
    KanjiPngError (..),
    renderKanjiPngError,
    kanjiPngPath,
  )
where

import Data.Text qualified as Text
import Nihongo.Kanji (Kanji, unKanji)
import Nihongo.Kanji.KanjiVg (findStrokeSvg, resolveKanjiVgRoot)
import Nihongo.Prelude
import Nihongo.Terminal.Image qualified as Image

-- | Caller-supplied knobs. Currently just the same KanjiVG root override
--   that 'resolveKanjiVgRoot' accepts; kept as a record so a future flag
--   (e.g. cache-dir override) can be added without breaking call sites.
newtype KanjiPngOptions = KanjiPngOptions
  { kanjivgDirOverride :: Maybe FilePath
  }
  deriving stock (Eq, Show)

defaultKanjiPngOptions :: KanjiPngOptions
defaultKanjiPngOptions = KanjiPngOptions {kanjivgDirOverride = Nothing}

-- | Every way 'kanjiPngPath' can fail. Each constructor carries enough
--   context to render a useful message without further IO.
data KanjiPngError
  = -- | None of override / @NIHONGO_KANJIVG_DIR@ / @./data/kanjivg@ exists.
    KpeKanjiVgRootMissing
  | -- | KanjiVG has no @<5-hex>.svg@ for this kanji.
    KpeSvgMissing !Kanji
  | -- | @rsvg-convert@ failed (missing on PATH, exit non-zero, etc.). The
    --   payload is the message @ensurePng@ returned, verbatim.
    KpeRasterise !Text
  deriving stock (Eq, Show)

-- | Format a 'KanjiPngError' into a single line of human-readable text
--   suitable for stderr.
renderKanjiPngError :: KanjiPngError -> Text
renderKanjiPngError = \case
  KpeKanjiVgRootMissing ->
    "could not find the KanjiVG corpus; see `nihongo help kanji-png`"
  KpeSvgMissing k ->
    "KanjiVG has no entry for " <> Text.singleton (unKanji k)
  KpeRasterise msg ->
    "failed to rasterise SVG: " <> msg

-- | Given a 'Kanji', return the absolute filesystem path to a cached PNG
--   of its KanjiVG glyph. Rasterises on cache miss; second and subsequent
--   calls for the same kanji are file-system cheap (a single
--   'doesFileExist' check inside @ensurePng@).
kanjiPngPath :: KanjiPngOptions -> Kanji -> IO (Either KanjiPngError FilePath)
kanjiPngPath opts kanji = do
  mRoot <- resolveKanjiVgRoot (kanjivgDirOverride opts)
  case mRoot of
    Nothing -> pure (Left KpeKanjiVgRootMissing)
    Just root -> do
      mSvg <- findStrokeSvg root kanji
      case mSvg of
        Nothing -> pure (Left (KpeSvgMissing kanji))
        Just svgPath -> do
          ensured <- Image.ensurePng svgPath
          pure $ case ensured of
            Left err -> Left (KpeRasterise err)
            Right png -> Right png
