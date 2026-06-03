let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/a3c59033a08c2eaef2cfba4a3c99fc9c192ca6d7/package.dhall
        sha256:18258ef583580a897f4af3e7c86db0342afb42fb40efc535b217ba1089230141

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
