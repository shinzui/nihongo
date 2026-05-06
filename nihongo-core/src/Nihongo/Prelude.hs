-- | Project-wide prelude for nihongo-core. Re-exports the standard toolkit
--   every module in this project is expected to use, so consumers can
--   `import Nihongo.Prelude` and get lens, generic-lens, common types, IO
--   helpers, and aeson basics without per-module import noise.
--
--   Note: `Data.Generics.Labels` is imported solely for its
--   `IsLabel name (Lens' s a)` instance (so `#field` resolves with
--   `OverloadedLabels`); it has no exported names to re-export.
module Nihongo.Prelude
  ( -- * Lens vocabulary
    module Control.Lens

    -- * Generic-lens vocabulary
  , module Data.Generics.Product
  , module Data.Generics.Sum

    -- * Common types
  , Text
  , Generic
  , NonEmpty (..)
  , UTCTime

    -- * IO
  , MonadIO (..)
  , getCurrentTime

    -- * Aeson basics
  , FromJSON
  , ToJSON
  ) where

import Control.Lens
import Control.Monad.IO.Class (MonadIO (..))
import Data.Aeson (FromJSON, ToJSON)
import Data.Generics.Labels ()
import Data.Generics.Product
import Data.Generics.Sum
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Time (UTCTime, getCurrentTime)
import GHC.Generics (Generic)
