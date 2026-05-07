{-# OPTIONS_GHC -Wno-orphans #-}

-- | KDL decoder and XDG-aware loader for the nihongo config file.
--
--   The config lives at @\$XDG_CONFIG_HOME/nihongo/config.kdl@ (defaults to
--   @~/.config/nihongo/config.kdl@ on macOS / Linux). A missing file is not
--   an error — the loader returns an empty 'NihongoConfig'. A malformed file
--   is an error.
module Nihongo.Config.Load
  ( loadNihongoConfig,
    decodeNihongoConfig,
    nihongoConfigDecoder,
    resolveAliases,
    configFilePath,
  )
where

import Control.Exception (try)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import KDL qualified
import Nihongo.Config.Types
import Nihongo.Prelude
import System.Directory (XdgDirectory (..), doesFileExist, getXdgDirectory)
import System.FilePath ((</>))

configFilePath :: IO FilePath
configFilePath = getXdgDirectory XdgConfig ("nihongo" </> "config.kdl")

-- | Load the nihongo config from the XDG location. A missing file resolves to
--   @NihongoConfig Nothing@ (no error); a malformed file produces a
--   'ConfigParseError'; a permission / IO failure produces a
--   'ConfigFileReadError'.
loadNihongoConfig :: IO (Either ConfigError NihongoConfig)
loadNihongoConfig = do
  path <- configFilePath
  exists <- doesFileExist path
  if not exists
    then pure (Right (NihongoConfig Nothing))
    else do
      readResult <- try @IOError (TIO.readFile path)
      case readResult of
        Left e -> pure (Left (ConfigFileReadError path (Text.pack (show e))))
        Right contents -> pure (decodeNihongoConfig contents)

decodeNihongoConfig :: Text -> Either ConfigError NihongoConfig
decodeNihongoConfig =
  firstE (ConfigParseError . KDL.renderDecodeError) . KDL.decodeWith nihongoConfigDecoder
  where
    firstE f = either (Left . f) Right

nihongoConfigDecoder :: KDL.DocumentDecoder NihongoConfig
nihongoConfigDecoder = KDL.document $ do
  a <- KDL.optional (KDL.node @AliasesSection "aliases")
  pure NihongoConfig {aliases = a}

-- | Decode the @aliases { … }@ block. Each child node's name is the alias
--   key; its first positional argument is the expansion. Within-file
--   duplicates collapse to the last occurrence ('KDL.remainingNodesWith'
--   collects repeated names into a list whose head is the most recently
--   declared value; the decoder takes 'listToMaybe' of each list).
instance KDL.DecodeNode AliasesSection where
  nodeDecoder = KDL.children $ do
    rawMap <- KDL.remainingNodesWith (KDL.arg @Text)
    pure AliasesSection {aliasMap = Map.mapMaybe listToMaybe rawMap}

resolveAliases :: NihongoConfig -> Map Text Text
resolveAliases = maybe Map.empty aliasMap . aliases
