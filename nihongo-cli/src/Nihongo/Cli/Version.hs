{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-overlapping-patterns #-}
-- The Right/Left match against the typed-TH `tGitInfoCwdTry` result is
-- intentionally dual-branched: when `.git` is present GHC sees the splice
-- as a static `Right` and marks `Left _` redundant; the same source must
-- compile under `nix build` (no `.git`) where the splice is `Left`. Per-file
-- suppression keeps -Wall noise out of every rebuild.

-- | Application version reporting for the nihongo CLI.
--
--   Two paths produce the short git SHA suffix:
--
--   1. *Cabal build path*. The `githash` library's `$$tGitInfoCwdTry`
--      typed-TH splice runs at compile time and returns
--      `Either String GitInfo`. When `.git` exists the splice succeeds; when
--      it does not (e.g. under `nix build` which strips `.git`), it returns
--      `Left` and we fall back to the CPP path.
--
--   2. *Nix build path*. A `-DGIT_HASH="abc1234"` GHC option supplied by the
--      flake compiles the SHA in as a literal. This path is unused until the
--      project ships as a Nix package.
module Nihongo.Cli.Version
  ( appVersion
  , appVersionWithGit
  , versionInfoOption
  ) where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Version (showVersion)
import GitHash (giHash, tGitInfoCwdTry)
import Options.Applicative (Parser, hidden, infoOption, long)
import Options.Applicative qualified as OA
import Paths_nihongo_cli (version)

appVersion :: Text
appVersion = Text.pack (showVersion version)

appVersionWithGit :: Text
appVersionWithGit =
  case gitSha of
    Just sha -> appVersion <> " (git: " <> sha <> ")"
    Nothing -> appVersion
  where
    gitSha :: Maybe Text
    gitSha =
#ifdef GIT_HASH
      Just (Text.pack GIT_HASH)
#else
      case $$tGitInfoCwdTry of
        Right gi -> Just (Text.take 7 (Text.pack (giHash gi)))
        Left _ -> Nothing
#endif

versionInfoOption :: Parser (a -> a)
versionInfoOption =
  infoOption
    (Text.unpack appVersionWithGit)
    ( long "version"
        <> OA.help "Print the version and exit"
        <> hidden
    )
