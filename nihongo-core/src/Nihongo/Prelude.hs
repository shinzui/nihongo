{-# LANGUAGE PackageImports #-}

-- | Project-wide prelude for nihongo. Re-exports the standard toolkit
--   every module is expected to use, so consumers can `import Nihongo.Prelude`
--   and get lens, generic-lens labels (`#field` syntax), common types, IO
--   helpers, and aeson basics without per-module import noise.
--
--   Pattern: `PackageImports` + `as X` aggregation; one re-export of
--   `Control.Lens` directly so the lens vocabulary is in scope unqualified.
module Nihongo.Prelude
  ( module X,
    module Control.Lens,
  )
where

import "aeson" Data.Aeson as X
  ( FromJSON,
    Options,
    SumEncoding (..),
    ToJSON,
    camelTo2,
    defaultOptions,
    fromJSON,
    genericParseJSON,
    genericToEncoding,
    genericToJSON,
    parseJSON,
    toEncoding,
    toJSON,
  )
import "base" Control.Applicative as X ((<|>))
import "base" Control.Monad as X (guard, unless, void, when)
import "base" Control.Monad.IO.Class as X (MonadIO, liftIO)
import "base" Data.List.NonEmpty as X (NonEmpty (..))
import "base" Data.Maybe as X (fromMaybe, isJust, isNothing)
import "base" Data.Proxy as X (Proxy (..))
import "base" GHC.Generics as X (Generic)
-- Enable #label syntax for Generic records.
import "generic-lens" Data.Generics.Labels ()
-- Re-export lens operators directly. Hide `argument` (the function-argument
-- setter) so that `Options.Applicative.argument` is unambiguous in CLI parsers.
import "lens" Control.Lens hiding (argument)
import "text" Data.Text as X (Text)
import "time" Data.Time as X (UTCTime, getCurrentTime)
