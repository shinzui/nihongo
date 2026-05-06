---
id: 3
slug: parse-kanjivg-stroke-order-metadata
title: "Parse KanjiVG stroke order metadata"
kind: exec-plan
created_at: 2026-05-06T02:27:18Z
intention: "intention_01kqxhfvpae3xv0dr9bnsxfdxs"
master_plan: "docs/masterplans/1-bootstrap-nihongo-cli-with-kanji-stroke-order.md"
---

# Parse KanjiVG stroke order metadata

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan `nihongo-core` carries a pure module
`Nihongo.Kanji.StrokeOrder` that takes the path to a KanjiVG SVG file and returns a
structured `StrokeOrderInfo` value: a list of strokes in their official order, each
labelled with the CJK Stroke character (`㇐`, `㇒`, `㇔`, etc.) plus a human-readable
English description ("horizontal", "left-falling", "dot"), and a component
decomposition tree drawn from the nested `<g kvg:element="...">` groups.

A consumer with that value in hand can render two things without ever looking at the
SVG again: a numbered, narrated stroke order ("1: ㇔ dot — 2: ㇔ dot — 3: ㇀ rising")
and a radical/component breakdown ("漢 = 氵 (left, radical) + 𦰩 (right, phonetic)").
EP-5 turns that into terminal output; this plan stops at the data structure and a
rich test suite.

KanjiVG SVGs use a custom XML namespace `kvg:` to attach stroke and component
metadata. The schema this plan parses is documented inline in Context and
Orientation; you do not need to consult external docs.

You will know it works when:

    cabal test nihongo-core

passes a suite of golden tests asserting specific values for at least three fixture
SVGs (a representative kanji like 漢, a hiragana like あ, and the simplest case
一).


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Milestone A: Build the CJK Stroke type → English description table.
- [ ] Milestone B: Implement `parseStrokeOrderText :: Text -> Either ParseError StrokeOrderInfo`.
- [ ] Milestone C: Implement `parseStrokeOrderFile :: FilePath -> IO (Either ParseError StrokeOrderInfo)`.
- [ ] Milestone D: Add a hspec test suite with three fixture SVGs (committed under `nihongo-core/test/fixtures/`).
- [ ] Milestone D: Manual sanity check parsing 漢 from the live submodule.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Use `xml-conduit` for SVG parsing.
  Rationale: KanjiVG SVGs declare a DOCTYPE and use a custom namespace; `xml-conduit`
  handles both correctly and is the de-facto Haskell XML library. `xeno` is faster
  but does not handle namespaces; `hxt` is heavier and less actively maintained.
  Date: 2026-05-05.

- Decision: Strip the `StrokeNumbers_*` group entirely; it is only useful for visual
  rendering, and EP-3 is about stroke ordering, not visual numerals.
  Rationale: We do not need stroke-number `<text>` nodes; the stroke ordering comes
  from the `id="kvg:<cp>-s<N>"` attribute on each `<path>`, sorted numerically.
  Date: 2026-05-05.

- Decision: Treat the `kvg:type` attribute as the *primary* per-stroke metadata, but
  do not fail if it is absent. Some variant SVGs omit it.
  Rationale: An unknown stroke type is still a valid stroke (the SVG path data is
  always present). Use `Nothing` for the description and let the consumer print a
  bare ordinal.
  Date: 2026-05-05.

- Decision: Strip the trailing alphabetic suffix (e.g. `a`, `b`) from `kvg:type`
  values before looking up the description. Suffixes refer to glyph-specific
  *variants* of a stroke type and the base stroke type is what the user wants to read.
  Preserve the raw value alongside.
  Rationale: Real SVGs (e.g. 漢) contain values like `㇑a`, `㇕b`, `㇐b`. The
  user-facing description should still say "vertical" or "turn-down" for those.
  Date: 2026-05-05.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan assumes EP-1 (`docs/plans/1-establish-nihongo-cli-foundations.md`) is
complete. It does not strictly require EP-2 (`docs/plans/2-add-kanjivg-submodule-and-lookup.md`)
because the parser takes a `FilePath` and works against any file on disk; the test
suite uses fixture SVGs committed under `nihongo-core/test/fixtures/` rather than the
submodule. In practice EP-2 will land first or in parallel, and EP-5 then composes
EP-2's `findStrokeSvg` with this plan's `parseStrokeOrderFile`.

The repository layout you can assume after EP-1 (and possibly EP-2):

    nihongo-core/
      nihongo-core.cabal
      src/Nihongo/Prelude.hs
      src/Nihongo/Kanji.hs                  # if EP-2 done
      src/Nihongo/Kanji/KanjiVg.hs          # if EP-2 done
    nihongo-cli/ ...

This plan adds two sibling modules under `nihongo-core/src/Nihongo/Kanji/` and a
test target.


### KanjiVG SVG schema (inline reference)

Real excerpt from `06f22.svg` (漢) — this is exactly what the parser walks:

    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE svg PUBLIC ... [
    <!ATTLIST g xmlns:kvg CDATA #FIXED "http://kanjivg.tagaini.net" ...>
    <!ATTLIST path xmlns:kvg CDATA #FIXED "http://kanjivg.tagaini.net" kvg:type CDATA #IMPLIED>
    ]>
    <svg xmlns="http://www.w3.org/2000/svg" width="109" height="109" viewBox="0 0 109 109">
      <g id="kvg:StrokePaths_06f22" style="...">
        <g id="kvg:06f22" kvg:element="漢">
          <g id="kvg:06f22-g1" kvg:element="氵" kvg:variant="true" kvg:original="水"
                                kvg:position="left"  kvg:radical="general">
            <path id="kvg:06f22-s1" kvg:type="㇔" d="M20,19.5..."/>
            <path id="kvg:06f22-s2" kvg:type="㇔" d="M15.25,44.12..."/>
            <path id="kvg:06f22-s3" kvg:type="㇀" d="M15.41,89.2..."/>
          </g>
          <g id="kvg:06f22-g2" kvg:position="right" kvg:phon="𦰩">
            <g id="kvg:06f22-g3" kvg:element="艹" kvg:variant="true" kvg:original="艸"
                                  kvg:position="top">
              <path id="kvg:06f22-s4"  kvg:type="㇐"  d="..."/>
              <path id="kvg:06f22-s5"  kvg:type="㇑a" d="..."/>
              <path id="kvg:06f22-s6"  kvg:type="㇑a" d="..."/>
            </g>
            <g id="kvg:06f22-g4" kvg:position="bottom">
              <g id="kvg:06f22-g5" kvg:element="口">
                <path id="kvg:06f22-s7"  kvg:type="㇑"  d="..."/>
                <path id="kvg:06f22-s8"  kvg:type="㇕b" d="..."/>
                <path id="kvg:06f22-s9"  kvg:type="㇐b" d="..."/>
              </g>
              <g id="kvg:06f22-g6" kvg:element="夫">
                <path id="kvg:06f22-s10" kvg:type="㇐"  d="..."/>
                <g id="kvg:06f22-g7" kvg:element="大">
                  <path id="kvg:06f22-s11" kvg:type="㇐"  d="..."/>
                  <path id="kvg:06f22-s12" kvg:type="㇒"  d="..."/>
                  <path id="kvg:06f22-s13" kvg:type="㇏"  d="..."/>
                </g>
              </g>
            </g>
          </g>
        </g>
      </g>
      <g id="kvg:StrokeNumbers_06f22" style="font-size:8;fill:#808080">
        <text transform="...">1</text>
        ...
      </g>
    </svg>

Salient facts:

- The XML namespace declaration sits on the `<g>` and `<path>` ATTLISTs in the
  DOCTYPE rather than on the root element — `xmlns:kvg CDATA #FIXED
  "http://kanjivg.tagaini.net"` (note: no trailing `/kanjivg.xsd`; some online docs
  say there is, but the actual in-repo SVGs use the bare URL above).
- Two top-level groups under `<svg>`: `kvg:StrokePaths_<cp>` (the actual paths) and
  `kvg:StrokeNumbers_<cp>` (decorative numerals). We parse only the first.
- Stroke order = the integer trailing the `id` attribute on each `<path>` element,
  in the form `kvg:<cp>-s<N>`. Sorting strokes by `N` gives canonical order.
- Stroke type = the `kvg:type` attribute. Its value is one Unicode CJK Stroke
  character (range U+31C0–U+31EF) optionally followed by a single ASCII letter
  (`a`, `b`, ...) marking a glyph-specific variant. Examples from the file above:
  `㇔` (U+31D4), `㇑a`, `㇕b`.
- Component tree = the nested `<g kvg:element="...">` groups under
  `kvg:StrokePaths_<cp>`. Each carries optional `kvg:position`, `kvg:radical`,
  `kvg:variant`, `kvg:original`, `kvg:phon` decorators.
- The `<g id="kvg:<cp>">` group (top of the tree, no `-gN` suffix) carries
  `kvg:element` equal to the kanji itself.


### CJK Stroke type table (inline reference)

The Unicode block "CJK Strokes" (U+31C0–U+31EF) names individual strokes. The table
below is the canonical version for this codebase; do not consult external sources at
build time.

    Char  Codepoint  Name (en)
    ----  ---------  -----------------------
    ㇀    U+31C0     rising
    ㇁    U+31C1     curve-down
    ㇂    U+31C2     slant
    ㇃    U+31C3     hook
    ㇄    U+31C4     wave
    ㇅    U+31C5     down-stroke
    ㇆    U+31C6     turn
    ㇇    U+31C7     turn-rise
    ㇈    U+31C8     curve-rise
    ㇉    U+31C9     curve-rise-hook
    ㇊    U+31CA     turn-down
    ㇋    U+31CB     turn-rise-hook
    ㇌    U+31CC     turn-curve-rise
    ㇍    U+31CD     curve-down-rise
    ㇎    U+31CE     turn-curve
    ㇏    U+31CF     right-falling
    ㇐    U+31D0     horizontal
    ㇑    U+31D1     vertical
    ㇒    U+31D2     left-falling
    ㇓    U+31D3     left-falling-curve
    ㇔    U+31D4     dot
    ㇕    U+31D5     turn-down
    ㇖    U+31D6     hook-up
    ㇗    U+31D7     turn-down-hook
    ㇘    U+31D8     turn-curve-up-down
    ㇙    U+31D9     vertical-hook
    ㇚    U+31DA     vertical-hook-down
    ㇛    U+31DB     turn-up-hook
    ㇜    U+31DC     turn-curve-down
    ㇝    U+31DD     curve-up
    ㇞    U+31DE     turn-curve
    ㇟    U+31DF     curve-up-hook
    ㇠    U+31E0     curve-down-hook
    ㇡    U+31E1     turn-curve-rise-hook
    ㇢    U+31E2     turn-down-curve
    ㇣    U+31E3     hook-down

Beginners' kanji largely use ㇐ horizontal, ㇑ vertical, ㇒ left-falling, ㇏
right-falling, ㇔ dot, ㇕ turn-down, ㇀ rising, and the variants thereof.


### `xml-conduit` 60-second crash course

`xml-conduit` parses XML into a `Document` and exposes namespaced names via the
`Name { nameLocalName, nameNamespace, namePrefix }` record. Key calls used in this
plan:

    Text.XML.parseLBS    :: ParseSettings -> ByteString -> Either SomeException Document
    Text.XML.documentRoot :: Document -> Element
    Text.XML.elementName       :: Element -> Name
    Text.XML.elementAttributes :: Element -> Map Name Text
    Text.XML.elementNodes      :: Element -> [Node]

The `Node` type is `NodeElement Element | NodeContent Text | NodeComment Text |
NodeInstruction _`. Helpers we will write filter `[Node]` to `[Element]`.

Pass `def { psDecodeEntities = decodeHtmlEntities }` to `parseLBS` so the DOCTYPE
ATTLIST entities resolve quietly.

The `kvg:` namespace name as it appears in parsed XML: an attribute key for
`kvg:type` parses to `Name { nameLocalName = "type", nameNamespace = Just
"http://kanjivg.tagaini.net", namePrefix = Just "kvg" }`. Match attributes by
constructing the expected `Name` value.


## Plan of Work

Four milestones. Implement them in order.


### Milestone A — Stroke type taxonomy

After this milestone `nihongo-core` exposes a constant lookup table from CJK Stroke
characters to English descriptions, plus a function that "normalises" raw `kvg:type`
values (strips the trailing variant letter).

Create `nihongo-core/src/Nihongo/Kanji/StrokeType.hs`:

    module Nihongo.Kanji.StrokeType
      ( StrokeType (..)
      , parseStrokeType
      , describeStrokeType
      ) where

    import qualified Data.Map.Strict as Map
    import Data.Map.Strict (Map)
    import qualified Data.Text as Text

    import Nihongo.Prelude

    -- | A normalised stroke type: the base CJK Stroke character (e.g. '㇐') plus
    --   the optional variant suffix (e.g. "a") that some KanjiVG entries carry.
    data StrokeType = StrokeType
      { baseChar :: Char
      , variant  :: Maybe Text
      }
      deriving stock (Eq, Show, Generic)

    -- | Parse the contents of a `kvg:type` attribute. The attribute is one CJK
    --   Stroke character optionally followed by ASCII letters.
    parseStrokeType :: Text -> Maybe StrokeType
    parseStrokeType raw =
      case Text.uncons raw of
        Nothing      -> Nothing
        Just (c, rs) ->
          Just (StrokeType c (if Text.null rs then Nothing else Just rs))

    -- | English description for a base stroke character. Returns Nothing if the
    --   character is not a known CJK Stroke. Variant suffixes are ignored.
    describeStrokeType :: StrokeType -> Maybe Text
    describeStrokeType (StrokeType c _) = Map.lookup c table

    table :: Map Char Text
    table = Map.fromList
      [ ('\x31C0', "rising")
      , ('\x31C1', "curve-down")
      , ('\x31C2', "slant")
      , ('\x31C3', "hook")
      , ('\x31C4', "wave")
      , ('\x31C5', "down-stroke")
      , ('\x31C6', "turn")
      , ('\x31C7', "turn-rise")
      , ('\x31C8', "curve-rise")
      , ('\x31C9', "curve-rise-hook")
      , ('\x31CA', "turn-down")
      , ('\x31CB', "turn-rise-hook")
      , ('\x31CC', "turn-curve-rise")
      , ('\x31CD', "curve-down-rise")
      , ('\x31CE', "turn-curve")
      , ('\x31CF', "right-falling")
      , ('\x31D0', "horizontal")
      , ('\x31D1', "vertical")
      , ('\x31D2', "left-falling")
      , ('\x31D3', "left-falling-curve")
      , ('\x31D4', "dot")
      , ('\x31D5', "turn-down")
      , ('\x31D6', "hook-up")
      , ('\x31D7', "turn-down-hook")
      , ('\x31D8', "turn-curve-up-down")
      , ('\x31D9', "vertical-hook")
      , ('\x31DA', "vertical-hook-down")
      , ('\x31DB', "turn-up-hook")
      , ('\x31DC', "turn-curve-down")
      , ('\x31DD', "curve-up")
      , ('\x31DE', "turn-curve")
      , ('\x31DF', "curve-up-hook")
      , ('\x31E0', "curve-down-hook")
      , ('\x31E1', "turn-curve-rise-hook")
      , ('\x31E2', "turn-down-curve")
      , ('\x31E3', "hook-down")
      ]

Add `Nihongo.Kanji.StrokeType` to `nihongo-core/nihongo-core.cabal` library
`exposed-modules`.

Acceptance: `cabal build all` succeeds. In `cabal repl nihongo-core`:

    >>> import Nihongo.Kanji.StrokeType
    >>> parseStrokeType "㇑a"
    Just (StrokeType {baseChar = '\x31D1', variant = Just "a"})
    >>> describeStrokeType <$> parseStrokeType "㇐"
    Just (Just "horizontal")


### Milestone B — Pure SVG-text parser

After this milestone `Nihongo.Kanji.StrokeOrder.parseStrokeOrderText` accepts the raw
text of a KanjiVG SVG and returns a parsed `StrokeOrderInfo`.

Add `xml-conduit ^>= 1.10` and `containers ^>= 0.7` to
`nihongo-core/nihongo-core.cabal`'s library `build-depends`. Add `bytestring ^>= 0.12`
as well; `xml-conduit` operates on `LByteString`.

Create `nihongo-core/src/Nihongo/Kanji/StrokeOrder.hs`:

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
    import qualified Data.ByteString.Lazy as LBS
    import Data.List (sortOn)
    import qualified Data.Map.Strict as Map
    import Data.Maybe (mapMaybe)
    import qualified Data.Text as Text
    import qualified Data.Text.Encoding as TE
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
      { strokes        :: [Stroke]
      , componentTree  :: ComponentTree
      }
      deriving stock (Eq, Show, Generic)

    data Stroke = Stroke
      { strokeIndex   :: Int
      , strokeRawType :: Maybe Text     -- e.g. "㇑a" exactly as written
      , strokeType    :: Maybe StrokeType
      , strokePathD   :: Text           -- the SVG path 'd' attribute
      }
      deriving stock (Eq, Show, Generic)

    newtype ComponentTree = ComponentTree
      { rootComponent :: Component
      }
      deriving stock (Eq, Show, Generic)

    data Component = Component
      { compElement   :: Maybe Text   -- kvg:element
      , compOriginal  :: Maybe Text   -- kvg:original
      , compPosition  :: Maybe Text   -- kvg:position
      , compRadical   :: Maybe Text   -- kvg:radical
      , compPhonetic  :: Maybe Text   -- kvg:phon
      , compChildren  :: [Component]
      , compStrokes   :: [Int]        -- stroke indices owned directly (not in children)
      }
      deriving stock (Eq, Show, Generic)

    data ParseError
      = MalformedXml Text
      | NoStrokePathsGroup
      | NoStrokesFound
      deriving stock (Eq, Show)

    -- | Parse the full text of a KanjiVG SVG file.
    parseStrokeOrderText :: Text -> Either ParseError StrokeOrderInfo
    parseStrokeOrderText t =
      case parseLBS settings (LBS.fromStrict (TE.encodeUtf8 t)) of
        Left err  -> Left (MalformedXml (Text.pack (show err)))
        Right doc -> fromDocument doc
      where
        settings = def { psDecodeEntities = decodeHtmlEntities }

    parseStrokeOrderFile :: FilePath -> IO (Either ParseError StrokeOrderInfo)
    parseStrokeOrderFile fp = do
      bs <- LBS.readFile fp
      pure $ case parseLBS settings bs of
        Left err  -> Left (MalformedXml (Text.pack (show err)))
        Right doc -> fromDocument doc
      where
        settings = def { psDecodeEntities = decodeHtmlEntities }

    -- Internal helpers below.

    kvgNS :: Text
    kvgNS = "http://kanjivg.tagaini.net"

    kvgAttr :: Text -> Name
    kvgAttr local = Name local (Just kvgNS) (Just "kvg")

    -- The "id"/"d" attributes have no namespace.
    plainAttr :: Text -> Name
    plainAttr local = Name local Nothing Nothing

    fromDocument :: Document -> Either ParseError StrokeOrderInfo
    fromDocument doc =
      let root = documentRoot doc
       in case findStrokePathsGroup root of
            Nothing -> Left NoStrokePathsGroup
            Just g  ->
              let allStrokes = sortOn strokeIndex (collectStrokes g)
              in if null allStrokes
                    then Left NoStrokesFound
                    else Right (StrokeOrderInfo allStrokes (buildComponentTree g))

    -- Find the `<g id="kvg:StrokePaths_*">` element among the root's children.
    findStrokePathsGroup :: Element -> Maybe Element
    findStrokePathsGroup root = lookForGroup (childElements root)
      where
        lookForGroup []     = Nothing
        lookForGroup (e:es) =
          case Map.lookup (plainAttr "id") (elementAttributes e) of
            Just v
              | Text.isPrefixOf "kvg:StrokePaths_" v -> Just e
            _ -> lookForGroup es

    childElements :: Element -> [Element]
    childElements e = mapMaybe asElement (elementNodes e)
      where
        asElement (NodeElement el) = Just el
        asElement _                 = Nothing

    -- Recursively walk all <path> nodes and turn them into Stroke records.
    collectStrokes :: Element -> [Stroke]
    collectStrokes = go
      where
        go e =
          let here =
                if Text.toLower (nameLocalName (elementName e)) == "path"
                  then maybe [] (:[]) (toStroke e)
                  else []
              kids = concatMap go (childElements e)
           in here <> kids

    toStroke :: Element -> Maybe Stroke
    toStroke e = do
      let attrs = elementAttributes e
      idVal <- Map.lookup (plainAttr "id") attrs
      idx   <- parseStrokeIndex idVal
      let raw = Map.lookup (kvgAttr "type") attrs
      let dval = maybe "" id (Map.lookup (plainAttr "d") attrs)
      pure Stroke
        { strokeIndex   = idx
        , strokeRawType = raw
        , strokeType    = raw >>= parseStrokeType
        , strokePathD   = dval
        }

    -- Parse "kvg:<cp>-s<N>" → N
    parseStrokeIndex :: Text -> Maybe Int
    parseStrokeIndex idVal =
      case Text.breakOnEnd "-s" idVal of
        (pfx, n)
          | not (Text.null pfx) -> readMaybe (Text.unpack n)
          | otherwise           -> Nothing

    -- Build the component tree by walking every <g> child of the StrokePaths group.
    buildComponentTree :: Element -> ComponentTree
    buildComponentTree strokePathsGroup =
      ComponentTree (toComponent (firstGElement strokePathsGroup))
      where
        firstGElement parent =
          case [e | e <- childElements parent, isG e] of
            (e:_) -> e
            []    -> parent

    toComponent :: Element -> Component
    toComponent el =
      let attrs = elementAttributes el
          gKids = filter isG (childElements el)
          pKids = filter isPath (childElements el)
       in Component
            { compElement  = Map.lookup (kvgAttr "element")  attrs
            , compOriginal = Map.lookup (kvgAttr "original") attrs
            , compPosition = Map.lookup (kvgAttr "position") attrs
            , compRadical  = Map.lookup (kvgAttr "radical")  attrs
            , compPhonetic = Map.lookup (kvgAttr "phon")     attrs
            , compChildren = map toComponent gKids
            , compStrokes  = mapMaybe (parseStrokeIndex <=< idAttr) pKids
            }
      where
        idAttr e = Map.lookup (plainAttr "id") (elementAttributes e)

    isG, isPath :: Element -> Bool
    isG    e = Text.toLower (nameLocalName (elementName e)) == "g"
    isPath e = Text.toLower (nameLocalName (elementName e)) == "path"

Add `Nihongo.Kanji.StrokeOrder` to `nihongo-core/nihongo-core.cabal` library
`exposed-modules`.

Note: `(<=<)` is `Control.Monad.(<=<)`, the right-to-left Kleisli composition. It's
imported explicitly because `Nihongo.Prelude` re-exports `Control.Lens` which does
not re-export `<=<`.

Acceptance: `cabal build all` succeeds. In `cabal repl nihongo-core`:

    >>> import qualified Data.Text.IO as TIO
    >>> import Nihongo.Kanji.StrokeOrder
    >>> txt <- TIO.readFile "data/kanjivg/kanji/06f22.svg"
    >>> let Right info = parseStrokeOrderText txt
    >>> length (strokes info)
    13
    >>> compElement (rootComponent (componentTree info))
    Just "\28450"   -- 漢


### Milestone C — IO wrapper

`parseStrokeOrderFile` is already defined inside the Milestone B module body. This
milestone is just a separate verification step:

    cabal repl nihongo-core
    >>> Right info <- parseStrokeOrderFile "data/kanjivg/kanji/06f22.svg"
    >>> mapM_ print (take 3 (strokes info))


### Milestone D — Test suite with fixture SVGs

After this milestone `cabal test` exercises the parser against three committed
fixture SVGs and asserts specific values.

Add a `test-suite` stanza to `nihongo-core/nihongo-core.cabal`:

    test-suite nihongo-core-tests
      import: common-options
      type: exitcode-stdio-1.0
      main-is: Main.hs
      hs-source-dirs: test
      other-modules:
        Test.Nihongo.Kanji.StrokeOrderSpec
      build-depends:
        base >=4.20 && <5,
        nihongo-core,
        bytestring ^>=0.12,
        hspec ^>=2.11,
        text ^>=2.1,

Copy three SVG files from `/Users/shinzui/Keikaku/hub/kanjivg/kanji/` (or from
`data/kanjivg/kanji/` if EP-2 has landed) into `nihongo-core/test/fixtures/`:

- `06f22.svg` (漢, 13 strokes, deeply nested component tree, includes `㇑a`/`㇕b`/`㇐b`
  variant suffixes)
- `03042.svg` (あ, 3 strokes, no components beyond the root)
- `04e00.svg` (一, 1 stroke, simplest possible case)

Although these are duplicated bytes (the originals also live under `data/kanjivg/`),
committing them under `test/fixtures/` makes the test suite robust against the
submodule being uninitialised. They are tiny (< 4 KB total). KanjiVG's CC-BY-SA-3.0
license is preserved by the attribution in the file headers (do not modify the
SVGs).

Create `nihongo-core/test/Main.hs`:

    module Main (main) where

    import Test.Hspec (hspec)
    import qualified Test.Nihongo.Kanji.StrokeOrderSpec as StrokeOrderSpec

    main :: IO ()
    main = hspec $ do
      StrokeOrderSpec.spec

Create `nihongo-core/test/Test/Nihongo/Kanji/StrokeOrderSpec.hs`:

    module Test.Nihongo.Kanji.StrokeOrderSpec (spec) where

    import qualified Data.Text.IO as TIO
    import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

    import Nihongo.Kanji.StrokeOrder
    import Nihongo.Kanji.StrokeType (StrokeType (..))

    spec :: Spec
    spec = describe "Nihongo.Kanji.StrokeOrder" $ do
      describe "漢 (06f22.svg)" $ do
        it "has 13 strokes in numeric order" $ do
          info <- loadFixture "06f22.svg"
          map strokeIndex (strokes info) `shouldBe` [1..13]

        it "first stroke is dot ㇔" $ do
          info <- loadFixture "06f22.svg"
          let s1 = head (strokes info)
          baseChar <$> strokeType s1 `shouldBe` Just '\x31D4'

        it "captures variant suffix on stroke 5 (㇑a)" $ do
          info <- loadFixture "06f22.svg"
          let s5 = strokes info !! 4
          variant <$> strokeType s5 `shouldBe` Just (Just "a")

        it "exposes 漢 at the root component" $ do
          info <- loadFixture "06f22.svg"
          compElement (rootComponent (componentTree info)) `shouldBe` Just "漢"

      describe "あ (03042.svg)" $ do
        it "has 3 strokes" $ do
          info <- loadFixture "03042.svg"
          length (strokes info) `shouldBe` 3

        it "exposes あ at the root component" $ do
          info <- loadFixture "03042.svg"
          compElement (rootComponent (componentTree info)) `shouldBe` Just "あ"

      describe "一 (04e00.svg)" $ do
        it "has 1 horizontal stroke" $ do
          info <- loadFixture "04e00.svg"
          length (strokes info) `shouldBe` 1
          baseChar <$> strokeType (head (strokes info))
            `shouldBe` Just '\x31D0'   -- ㇐

      describe "error reporting" $ do
        it "rejects empty input" $ do
          parseStrokeOrderText "" `shouldSatisfy` isLeft

    loadFixture :: FilePath -> IO StrokeOrderInfo
    loadFixture name = do
      txt <- TIO.readFile ("test/fixtures/" <> name)
      case parseStrokeOrderText txt of
        Right info -> pure info
        Left err   -> error (show err)

    isLeft :: Either a b -> Bool
    isLeft (Left _) = True
    isLeft _        = False

Run:

    cabal test all

Acceptance: every spec item passes. The suite reports something like
"7 examples, 0 failures".


## Concrete Steps

Run from the repo root.

Milestone A:

    # Create nihongo-core/src/Nihongo/Kanji/StrokeType.hs.
    # Add to exposed-modules.
    cabal build all

Milestone B & C:

    # Create nihongo-core/src/Nihongo/Kanji/StrokeOrder.hs.
    # Add it to exposed-modules. Add xml-conduit + containers + bytestring deps.
    cabal build all
    cabal repl nihongo-core
    # then in the repl, run the spot-checks under "Acceptance" above.

Milestone D:

    mkdir -p nihongo-core/test/fixtures
    cp /Users/shinzui/Keikaku/hub/kanjivg/kanji/06f22.svg nihongo-core/test/fixtures/
    cp /Users/shinzui/Keikaku/hub/kanjivg/kanji/03042.svg nihongo-core/test/fixtures/
    cp /Users/shinzui/Keikaku/hub/kanjivg/kanji/04e00.svg nihongo-core/test/fixtures/
    # (alternatively copy from data/kanjivg/kanji/ once EP-2 lands)
    # Create nihongo-core/test/Main.hs and the Spec module.
    # Edit nihongo-core/nihongo-core.cabal to add the test-suite stanza.
    cabal test all

Expected: build succeeds; `cabal test all` ends in `Test suite nihongo-core-tests:
PASS`.


## Validation and Acceptance

At the level of behaviour: every stroke from the 13 strokes in 漢 is captured, each
with its 1-indexed `strokeIndex` and its base CJK Stroke character. The variant
suffix on stroke 5 (`㇑a`) is preserved as `variant = Just "a"` and the base lookup
still returns `"vertical"`. Stroke 1's `strokeType` resolves to `Just (StrokeType
{ baseChar = '㇔', variant = Nothing })`, and `describeStrokeType` of that returns
`Just "dot"`.

For あ the parser returns 3 strokes and the root component carries `compElement =
Just "あ"`. For 一 the parser returns 1 stroke whose base character is ㇐ and whose
description is `"horizontal"`.

The test suite catches three classes of regression:

- A change to the schema-walking code that misses one stroke (e.g. forgetting to
  recurse into nested groups) would fail the "has 13 strokes" assertion for 漢.
- A change that drops the variant suffix would fail the "captures variant suffix"
  assertion.
- A change that misnames the kvg namespace URL would fail every `compElement`
  assertion (root would be `Nothing`).

Manual sanity check at the REPL with the live submodule (run from project root with
EP-2 complete; otherwise this step is optional):

    >>> import Nihongo.Kanji.StrokeOrder
    >>> import Nihongo.Kanji.StrokeType (describeStrokeType)
    >>> Right info <- parseStrokeOrderFile "data/kanjivg/kanji/06f22.svg"
    >>> mapM_ (\s -> putStrLn (show (strokeIndex s) <> ": " <> show (describeStrokeType =<< strokeType s))) (strokes info)
    1: Just "dot"
    2: Just "dot"
    3: Just "rising"
    4: Just "horizontal"
    5: Just "vertical"
    6: Just "vertical"
    7: Just "vertical"
    8: Just "turn-down"
    9: Just "horizontal"
    10: Just "horizontal"
    11: Just "horizontal"
    12: Just "left-falling"
    13: Just "right-falling"


## Idempotence and Recovery

The parser is pure; running it twice on the same input is identical. The IO wrapper
reads the file each time; it does not cache. EP-4 owns rasterisation caching, not
this plan.

If `xml-conduit` produces a parse error, inspect the error text — common causes:

- An SVG with a malformed DOCTYPE (rare; the corpus is well-formed). Workaround: use
  the "stripped" KanjiVG release that omits the DOCTYPE; record that fallback in this
  plan's Decision Log if you need it.
- An SVG fetched from outside the corpus that is not a KanjiVG file. The parser is
  shape-strict — it requires a `<g id="kvg:StrokePaths_*">` element — and will return
  `Left NoStrokePathsGroup`.

Test fixtures are committed under git; if they are accidentally deleted, copy them
back from `/Users/shinzui/Keikaku/hub/kanjivg/kanji/` or from
`data/kanjivg/kanji/` once EP-2 lands.


## Interfaces and Dependencies

Cabal dependencies added:

- `nihongo-core/nihongo-core.cabal` library: `xml-conduit ^>= 1.10`, `containers ^>=
  0.7`, `bytestring ^>= 0.12`. (`text` is already present.)
- `nihongo-core/nihongo-core.cabal` test-suite: `hspec ^>= 2.11`, `bytestring`,
  `text`, `nihongo-core` (self).

Exposed modules added: `Nihongo.Kanji.StrokeType`, `Nihongo.Kanji.StrokeOrder`.

Public APIs subsequent ExecPlans rely on:

- `Nihongo.Kanji.StrokeOrder.StrokeOrderInfo` (record type).
- `Nihongo.Kanji.StrokeOrder.Stroke` (record type with `strokeIndex`,
  `strokeRawType`, `strokeType`, `strokePathD`).
- `Nihongo.Kanji.StrokeOrder.Component` and `ComponentTree` (record types).
- `Nihongo.Kanji.StrokeOrder.parseStrokeOrderText :: Text -> Either ParseError StrokeOrderInfo`.
- `Nihongo.Kanji.StrokeOrder.parseStrokeOrderFile :: FilePath -> IO (Either ParseError StrokeOrderInfo)`.
- `Nihongo.Kanji.StrokeType.StrokeType`, `parseStrokeType`, `describeStrokeType`.

EP-5 will combine `EP-2.findStrokeSvg` and `parseStrokeOrderFile` to render text
output, and will use `describeStrokeType <$> strokeType` to label each stroke.

Files added by this plan:

    nihongo-core/src/Nihongo/Kanji/StrokeType.hs
    nihongo-core/src/Nihongo/Kanji/StrokeOrder.hs
    nihongo-core/test/Main.hs
    nihongo-core/test/Test/Nihongo/Kanji/StrokeOrderSpec.hs
    nihongo-core/test/fixtures/06f22.svg
    nihongo-core/test/fixtures/03042.svg
    nihongo-core/test/fixtures/04e00.svg
