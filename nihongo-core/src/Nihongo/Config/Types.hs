-- | Parse model and error type for the nihongo KDL config file.
--
--   Today the only top-level section is @aliases { … }@; the type is shaped
--   to allow more sections later without breaking the schema.
module Nihongo.Config.Types
  ( NihongoConfig (..),
    AliasesSection (..),
    ConfigError (..),
  )
where

import Data.Map.Strict (Map)
import Nihongo.Prelude

data NihongoConfig = NihongoConfig
  { aliases :: !(Maybe AliasesSection)
  }
  deriving stock (Generic, Show, Eq)

-- | Parse model for the @aliases { … }@ block. Each child node's name is the
--   alias key; its first positional argument is the expansion. Within-file
--   duplicates collapse to the last occurrence (the decoder uses
--   'KDL.remainingNodesWith', which yields a @Map Text [Text]@ whose head is
--   the most recently declared value; the decoder takes 'listToMaybe').
newtype AliasesSection = AliasesSection
  { aliasMap :: Map Text Text
  }
  deriving stock (Generic, Show, Eq)

data ConfigError
  = ConfigParseError !Text
  | ConfigFileReadError !FilePath !Text
  deriving stock (Generic, Show, Eq)
