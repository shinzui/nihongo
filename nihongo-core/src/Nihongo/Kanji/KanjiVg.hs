-- | KanjiVG corpus lookup. Resolves the on-disk root directory and maps a
--   'Kanji' to the absolute path of its KanjiVG SVG (`<5-hex>.svg` under
--   `kanji/`). The resolution priority is: explicit override
--   (`--kanjivg-dir`-style), `NIHONGO_KANJIVG_DIR` env var, then
--   `<cwd>/data/kanjivg`.
module Nihongo.Kanji.KanjiVg
  ( KanjiVgRoot (..)
  , defaultKanjiVgRoot
  , resolveKanjiVgRoot
  , findStrokeSvg
  ) where

import Data.Text qualified as Text
import System.Directory (doesDirectoryExist, doesFileExist, getCurrentDirectory)
import System.Environment (lookupEnv)
import System.FilePath ((</>))

import Nihongo.Kanji (Kanji, kanjiCodepointHex)
import Nihongo.Prelude ()

-- | Absolute filesystem path to the KanjiVG checkout. Must contain a
--   @kanji/@ subdirectory of @<5-hex>.svg@ files.
newtype KanjiVgRoot = KanjiVgRoot {rootPath :: FilePath}
  deriving stock (Eq, Show)

-- | Resolve the KanjiVG root using the priority order:
--
--     1. the explicit override (e.g. from @--kanjivg-dir@)
--     2. the @NIHONGO_KANJIVG_DIR@ env var
--     3. @<cwd>/data/kanjivg@
--
--   Returns 'Nothing' if none of those exist on disk.
resolveKanjiVgRoot :: Maybe FilePath -> IO (Maybe KanjiVgRoot)
resolveKanjiVgRoot override = do
  mEnv <- lookupEnv "NIHONGO_KANJIVG_DIR"
  cwd <- getCurrentDirectory
  let candidates =
        [ p
        | Just p <-
            [ override
            , mEnv
            , Just (cwd </> "data" </> "kanjivg")
            ]
        , not (null p)
        ]
  pickFirstExisting candidates
  where
    pickFirstExisting [] = pure Nothing
    pickFirstExisting (p : ps) = do
      ok <- doesDirectoryExist (p </> "kanji")
      if ok then pure (Just (KanjiVgRoot p)) else pickFirstExisting ps

-- | Convenience: resolve the root with no override. Errors loudly if no
--   candidate exists, since most callers cannot meaningfully proceed without
--   the corpus.
defaultKanjiVgRoot :: IO KanjiVgRoot
defaultKanjiVgRoot = do
  mr <- resolveKanjiVgRoot Nothing
  case mr of
    Just r -> pure r
    Nothing -> ioError (userError msg)
  where
    msg =
      unlines
        [ "Could not find the KanjiVG corpus."
        , "Tried, in order:"
        , "  1. NIHONGO_KANJIVG_DIR env var"
        , "  2. ./data/kanjivg (relative to current working directory)"
        , "Run `git submodule update --init data/kanjivg` from the project root,"
        , "or set NIHONGO_KANJIVG_DIR to point at a KanjiVG checkout."
        ]

-- | Look up the SVG path for a 'Kanji'. Returns 'Nothing' if the file is
--   absent (KanjiVG does not cover every Unicode CJK codepoint).
findStrokeSvg :: KanjiVgRoot -> Kanji -> IO (Maybe FilePath)
findStrokeSvg (KanjiVgRoot root) k = do
  let hex = Text.unpack (kanjiCodepointHex k)
      path = root </> "kanji" </> (hex <> ".svg")
  ok <- doesFileExist path
  pure (if ok then Just path else Nothing)
