let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/1f70781427426c09673d46f8e6733b7e7d0abedc/package.dhall
        sha256:3b79aae9216456678300441ca8616b64a4b4fa520a1286dfcc418f60899d5d4a

in  Schema.Project::{
    , project = Schema.ProjectIdentity::{
      , name = "nihongo"
      , namespace = "shinzui"
      , type = Schema.PackageType.Application
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , description = Some
          "A terminal-first Japanese learning companion for kanji, vocabulary, reading, and daily study workflows"
      , domains = [ "Language Learning", "CLI" ]
      , owners = [ "shinzui" ]
      }
    , repos = [ Schema.Repo::{ name = "nihongo" } ]
    , packages =
      [ Schema.Package::{
        , name = "nihongo-core"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "nihongo-core"
        , description = Some
            "Core library: domain types, business logic, and Nihongo.Prelude"
        }
      , Schema.Package::{
        , name = "nihongo-cli"
        , type = Schema.PackageType.Application
        , language = Schema.Language.Haskell
        , path = Some "nihongo-cli"
        , description = Some
            "Command-line interface; ships the `nihongo` executable"
        , dependencies =
          [ Schema.Dependency.ByName "shinzui/nihongo:nihongo-core" ]
        }
      ]
    , dependencies =
      [ "ekmett/lens", "pcapriotti/optparse-applicative" ]
    }
