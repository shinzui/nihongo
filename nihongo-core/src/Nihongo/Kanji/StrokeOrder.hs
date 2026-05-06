-- | Parse a KanjiVG SVG file into a 'StrokeOrderInfo' value: an ordered
--   list of strokes (each tagged with its CJK Stroke type and raw SVG path
--   data) and a recursive 'ComponentTree' describing the kanji's
--   radical/component decomposition.
--
--   This module knows nothing about terminals or CLIs; it is purely a
--   data-extraction layer. EP-5 composes 'parseStrokeOrderFile' with the
--   KanjiVG lookup from "Nihongo.Kanji.KanjiVg" to drive @kanji show@.
module Nihongo.Kanji.StrokeOrder
  ( StrokeOrderInfo (..)
  , Stroke (..)
  , Component (..)
  , ComponentTree (..)
  , ParseError (..)
  , parseStrokeOrderText
  , parseStrokeOrderFile
  ) where

import Control.Monad ((<=<))
import Data.ByteString.Lazy qualified as LBS
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Text.Read (readMaybe)
import Text.XML
  ( Document
  , Element (..)
  , Name (..)
  , Node (..)
  , def
  , documentRoot
  , parseLBS
  , psDecodeEntities
  )
import Text.XML.Stream.Parse (decodeHtmlEntities)

import Nihongo.Kanji.StrokeType (StrokeType, parseStrokeType)
import Nihongo.Prelude

data StrokeOrderInfo = StrokeOrderInfo
  { strokes :: ![Stroke]
  , componentTree :: !ComponentTree
  }
  deriving stock (Eq, Show, Generic)

data Stroke = Stroke
  { strokeIndex :: !Int
  , strokeRawType :: !(Maybe Text)
  , strokeType :: !(Maybe StrokeType)
  , strokePathD :: !Text
  }
  deriving stock (Eq, Show, Generic)

newtype ComponentTree = ComponentTree
  { rootComponent :: Component
  }
  deriving stock (Eq, Show, Generic)

data Component = Component
  { compElement :: !(Maybe Text)
  , compOriginal :: !(Maybe Text)
  , compPosition :: !(Maybe Text)
  , compRadical :: !(Maybe Text)
  , compPhonetic :: !(Maybe Text)
  , compChildren :: ![Component]
  , compStrokes :: ![Int]
  }
  deriving stock (Eq, Show, Generic)

data ParseError
  = MalformedXml !Text
  | NoStrokePathsGroup
  | NoStrokesFound
  deriving stock (Eq, Show)

-- | Parse the full text of a KanjiVG SVG file.
parseStrokeOrderText :: Text -> Either ParseError StrokeOrderInfo
parseStrokeOrderText t =
  case parseLBS settings (LBS.fromStrict (TE.encodeUtf8 t)) of
    Left err -> Left (MalformedXml (Text.pack (show err)))
    Right doc -> fromDocument doc
  where
    settings = def {psDecodeEntities = decodeHtmlEntities}

parseStrokeOrderFile :: FilePath -> IO (Either ParseError StrokeOrderInfo)
parseStrokeOrderFile fp = do
  bs <- LBS.readFile fp
  pure $ case parseLBS settings bs of
    Left err -> Left (MalformedXml (Text.pack (show err)))
    Right doc -> fromDocument doc
  where
    settings = def {psDecodeEntities = decodeHtmlEntities}

-- | KanjiVG SVGs declare @xmlns:kvg@ via a DTD @#FIXED@ ATTLIST default
--   rather than as a regular @xmlns@ attribute on the root. @xml-conduit@
--   does not apply DTD defaults when resolving namespace prefixes, so
--   @kvg:type@ parses as @Name "type" Nothing (Just "kvg")@ — i.e. with
--   the prefix preserved but the namespace URL absent. Matching on the
--   prefix is therefore the right shape for KanjiVG attribute lookups.
kvgAttr :: Text -> Name
kvgAttr local = Name local Nothing (Just "kvg")

plainAttr :: Text -> Name
plainAttr local = Name local Nothing Nothing

fromDocument :: Document -> Either ParseError StrokeOrderInfo
fromDocument doc =
  let root = documentRoot doc
   in case findStrokePathsGroup root of
        Nothing -> Left NoStrokePathsGroup
        Just g ->
          let allStrokes = sortOn strokeIndex (collectStrokes g)
           in if null allStrokes
                then Left NoStrokesFound
                else Right (StrokeOrderInfo allStrokes (buildComponentTree g))

findStrokePathsGroup :: Element -> Maybe Element
findStrokePathsGroup root = lookForGroup (childElements root)
  where
    lookForGroup [] = Nothing
    lookForGroup (e : es) =
      case Map.lookup (plainAttr "id") (elementAttributes e) of
        Just v
          | Text.isPrefixOf "kvg:StrokePaths_" v -> Just e
        _ -> lookForGroup es

childElements :: Element -> [Element]
childElements e = mapMaybe asElement (elementNodes e)
  where
    asElement (NodeElement el) = Just el
    asElement _ = Nothing

collectStrokes :: Element -> [Stroke]
collectStrokes = go
  where
    go e =
      let here =
            if Text.toLower (nameLocalName (elementName e)) == "path"
              then maybe [] (: []) (toStroke e)
              else []
          kids = concatMap go (childElements e)
       in here <> kids

toStroke :: Element -> Maybe Stroke
toStroke e = do
  let attrs = elementAttributes e
  idVal <- Map.lookup (plainAttr "id") attrs
  idx <- parseStrokeIndex idVal
  let raw = Map.lookup (kvgAttr "type") attrs
      dval = maybe "" id (Map.lookup (plainAttr "d") attrs)
  pure
    Stroke
      { strokeIndex = idx
      , strokeRawType = raw
      , strokeType = raw >>= parseStrokeType
      , strokePathD = dval
      }

-- | Parse @"kvg:<cp>-s<N>"@ → @N@.
parseStrokeIndex :: Text -> Maybe Int
parseStrokeIndex idVal =
  case Text.breakOnEnd "-s" idVal of
    (pfx, n)
      | not (Text.null pfx) -> readMaybe (Text.unpack n)
      | otherwise -> Nothing

buildComponentTree :: Element -> ComponentTree
buildComponentTree strokePathsGroup =
  ComponentTree (toComponent (firstGElement strokePathsGroup))
  where
    firstGElement parent =
      case [e | e <- childElements parent, isG e] of
        (e : _) -> e
        [] -> parent

toComponent :: Element -> Component
toComponent el =
  let attrs = elementAttributes el
      gKids = filter isG (childElements el)
      pKids = filter isPath (childElements el)
   in Component
        { compElement = Map.lookup (kvgAttr "element") attrs
        , compOriginal = Map.lookup (kvgAttr "original") attrs
        , compPosition = Map.lookup (kvgAttr "position") attrs
        , compRadical = Map.lookup (kvgAttr "radical") attrs
        , compPhonetic = Map.lookup (kvgAttr "phon") attrs
        , compChildren = map toComponent gKids
        , compStrokes = mapMaybe (parseStrokeIndex <=< idAttr) pKids
        }
  where
    idAttr e = Map.lookup (plainAttr "id") (elementAttributes e)

isG, isPath :: Element -> Bool
isG e = Text.toLower (nameLocalName (elementName e)) == "g"
isPath e = Text.toLower (nameLocalName (elementName e)) == "path"
