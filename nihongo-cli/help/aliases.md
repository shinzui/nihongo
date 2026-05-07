# Command Aliases

nihongo can expand short aliases for longer command invocations
before parsing. Aliases live in:

    $XDG_CONFIG_HOME/nihongo/config.kdl
    # macOS / Linux default: ~/.config/nihongo/config.kdl

## SCHEMA

The file is in KDL (https://kdl.dev). Aliases live inside an
`aliases { … }` block. Each child node's name is the alias key;
its first quoted argument is the expansion:

    aliases {
      ks "kanji show"
      kp "kanji png"
      h  "help"
    }

The expansion is split on whitespace, so it cannot contain
arguments with embedded spaces. Use a shell alias for that case.

## EXPANSION RULES

Only the first argument is matched. Trailing arguments are
appended to the expansion. So with the example above:

    nihongo ks 漢   →   nihongo kanji show 漢

Expansion is single-pass. If `a` expands to `b foo` and `b`
expands to `c bar`, then `nihongo a x` becomes `nihongo b foo x`,
not `nihongo c bar foo x`.

## BUILT-IN PROTECTION

Built-in command names (`hello`, `help`, `completions`, `kanji`,
`alias`) cannot be shadowed. An alias whose name is one of these
is silently ignored at expansion time.

Argv whose first token starts with `-` is also left alone, so
`--version`, `--help`, and shell-completion entry paths
(`--bash-completion-index …`) are never treated as aliases.

## PRECEDENCE

Within one file, if the same alias name appears twice, the last
occurrence wins.

## INSPECTING THE RESOLVED MAP

Run `nihongo alias list` to print the resolved alias table:

    $ nihongo alias list
    h  = help
    kp = kanji png
    ks = kanji show

The names are padded so the `=` separators align, and the entries
are sorted ascending by alias name. If no config file exists, or
the file contains no `aliases { … }` block, the output is:

    No aliases configured.
