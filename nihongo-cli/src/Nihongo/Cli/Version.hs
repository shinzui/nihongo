{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Application version reporting for the nihongo CLI.
--
--   Two paths produce the short git SHA suffix. When `.git` exists at
--   compile time the `githash` typed-TH splice succeeds; when it does not
--   (e.g. under `nix build`, which strips `.git`), the splice returns
--   `Left` and a CPP `#ifdef GIT_HASH` fallback compiles the SHA in via
--   `-DGIT_HASH=...` supplied by the flake. When neither is available the
--   bare cabal version is reported.
module Nihongo.Cli.Version
  ( appVersion,
    appVersionWithGit,
    gitCommitShort,
    versionInfoOption,
  )
where

import Data.Text (pack)
import Data.Text qualified as Text
import Data.Version (showVersion)
import GitHash (GitInfo, giHash, tGitInfoCwdTry)
import Nihongo.Prelude
import Options.Applicative
import Paths_nihongo_cli (version)

appVersion :: Text
appVersion = pack (showVersion version)

gitInfo :: Either String GitInfo
gitInfo = $$tGitInfoCwdTry

nixGitHash :: Maybe Text
#ifdef GIT_HASH
nixGitHash = Just GIT_HASH
#else
nixGitHash = Nothing
#endif

gitCommitShort :: Maybe Text
gitCommitShort = case gitInfo of
  Right gi -> Just $ pack $ take 7 $ giHash gi
  Left _ -> nixGitHash

appVersionWithGit :: Text
appVersionWithGit = "nihongo " <> appVersion <> commitSuffix
  where
    commitSuffix = maybe "" (\c -> " (git: " <> c <> ")") gitCommitShort

versionInfoOption :: Parser (a -> a)
versionInfoOption =
  infoOption
    (Text.unpack appVersionWithGit)
    ( long "version"
        <> help "Print the version and exit"
        <> hidden
    )
