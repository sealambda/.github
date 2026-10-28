# Toolchain

The organization's toolchain flake: the tools that every repository builds
with, at one version line, and the formatters and linters that every
repository runs. This page is the reference for a repository that consumes
it.

## Consume it

A repository takes a tag of this flake as an input and follows its nixpkgs,
so that the toolchain's lock file is the only pin of nixpkgs:

```nix
{
  inputs = {
    toolchain.url = "github:sealambda/.github?dir=toolchain&ref=toolchain-vN";
    nixpkgs.follows = "toolchain/nixpkgs";
    treefmt-nix.follows = "toolchain/treefmt-nix";
  };
}
```

## Outputs

| Output                             | What it is                                                                                                                                                                      |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages.<system>.<tool>`         | `nodejs`, `pnpm`, `erlang`, `elixir`, `hex`, `postgresql`, `opentofu`, `cosign` ([packages.nix](packages.nix))                                                                  |
| `packages.<system>.pnpm-only-lint` | The pnpm-only lint ([pnpm-only-lint.sh](pnpm-only-lint.sh)). Run it with `nix run …#pnpm-only-lint -- <directory>`.                                                             |
| `devShells.<system>.default`       | A shell with every tool of `packages`. Add it to a shell with `inputsFrom`.                                                                                                     |
| `lib.systems`                      | The supported systems: `aarch64-darwin`, `aarch64-linux` and `x86_64-linux`. Use it for the `systems` of your own flake.                                                        |
| `lib.versions`                     | The version line: the exact version of each tool, as built for x86_64-linux. Read it with `nix eval --json …#lib.versions`.                                                     |
| `lib.treefmtModules.default`       | The organization's formatters and linters, as a treefmt-nix module ([treefmt.nix](treefmt.nix)).                                                                                |
| `lib.treefmtModules.elixir`        | `mix format` with the toolchain's Elixir ([treefmt-elixir.nix](treefmt-elixir.nix)).                                                                                            |
| `lib.devShellPathCheck pkgs shell` | A check that fails when `shell` provides a command of [package-managers.nix](package-managers.nix) on its build PATH. See below.                                                |
| `checks.<system>`                  | `version-line`, `version-policy`, `pnpm-only-lint`, `dev-shell-path`, `dev-shell-path-cases`, `mix-format`, `hex`, `pnpm-package`, `bash-strict-mode` and `shell-script-names`. |

`lib` holds the treefmt modules because Nix warns about an unknown flake
output name such as `treefmtModules`.

## Version policy

- Each tool comes from a versioned nixpkgs attribute where one exists
  (`nodejs-slim_26`, `pnpm_12`, `postgresql_18`,
  `beam.packages.erlang_29.elixir_1_20`), so that a lock refresh moves only
  within a major.
- [versions.nix](versions.nix) names the series of each tool: a major, a
  minor (OpenTofu) or an exact version (cosign). The `version-line` check
  fails when a lock refresh moves a tool out of its series, and when a system
  builds another version than `lib.versions`. A move to a new series is a
  reviewed edit of `packages.nix` and `versions.nix`.
- The `pnpm` package links only `pnpm` and `pn`. pnpm's `pnpx` and `pnx`
  aliases run `pnpm dlx`, which runs a package that no lock file pins. The
  package is a set of links to nixpkgs' pnpm, not an override of it: nixpkgs
  compiles pnpm 12 from source, and an override would make every consumer
  compile it too.
- `nodejs-slim` ships neither npm nor corepack.
- `hex` is Hex built for the toolchain's Elixir, and the shell finds it
  through `ERL_LIBS`. `mix hex.info`, `mix deps.get` and `mix hex.audit` use
  this Hex and do not download the newest one into `MIX_HOME`.

## Formatters and linters

`lib.treefmtModules.default` runs these programs. The versions are those of
the locked nixpkgs (`nix eval --raw …#…`, or `--version` in `nix develop`).

| Files                                    | Program                                                                             | Role                      |
| ---------------------------------------- | ----------------------------------------------------------------------------------- | ------------------------- |
| `*.nix`                                  | nixfmt (RFC 166 style), statix, deadnix                                             | format, lint, unused code |
| `*.sh`, `*.bash`                         | shfmt, ShellCheck, bash-strict-mode                                                 | format, lint, strict mode |
| `*.md`, `*.yaml`, `*.yml`, `*.json`      | Prettier                                                                            | format                    |
| `*.yaml`, `*.yml`                        | yamllint                                                                            | lint                      |
| GitHub workflows, actions and Dependabot | actionlint (with ShellCheck), zizmor (pedantic, offline)                            | lint                      |
| every file                               | typos, `editorconfig-checker`, pre-commit-hooks' shebang checks, shell-script-names | lint                      |

A formatter runs first (priority 0) and a linter checks its result
(priority 1). Lock files (`*.lock`, `pnpm-lock.yaml`) are excluded.

## Conventions that the checks enforce

### Shell scripts

- **Dialect.** Bash only, as the
  [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
  requires. ShellCheck takes the dialect from the shebang.
- **Shebang.** An executable script starts with `#!/usr/bin/env bash`. This
  differs from the guide's `#!/bin/bash` on purpose: NixOS has no
  `/bin/bash`, and `env` finds the Bash of the development shell.
- **Strict mode.** The first command of an executable script is exactly
  `set -euo pipefail`, so that an unset variable, a failed command or a
  failed pipeline stage stops the script. The guide does not require it; the
  organization does. Only this line is accepted: `bash-strict-mode` rejects
  equivalent forms such as `set -Eeuo pipefail`, so that every script starts
  the same way.
- **Executable bit.** A file with a shebang is executable, and an executable
  file has a shebang.
- **Libraries.** A file that is sourced is not executable, has no shebang
  and sets no shell options. It starts with `# shellcheck shell=bash`, which
  gives ShellCheck the dialect. `bash-strict-mode` fails a library that has
  a line in column 0 with `set -…`, `set +…` or `shopt -s`; `set --`
  (positional parameters) and an indented line in a function are allowed.
- **Style.** The guide's style, through `.editorconfig`: 2 spaces, `; then`
  on the `if` line, an operator that breaks a pipeline starts the next line,
  indented `case` patterns. ShellCheck also runs the guide's optional checks:
  `"${var}"` braces, `[[ ]]`, quoted variables, `-n` tests, unmasked return
  values, a default `case` branch and `command -v`. It also runs
  `check-set-e-suppressed` (SC2310, SC2311): `set -e` has no effect inside a
  function that runs as an `if` condition or before `||`. A function that
  must stop the script runs as a plain statement, and reports a finding by
  raising a counter that the caller reads at the end.
- **Names.** Every shell script in a repository has the `.sh` extension:
  executables and libraries alike. A name without an extension is only for
  a program that a package installs on PATH, such as `pnpm-only-lint`, which
  is built from a `.sh` file. The `shell-script-names` linter fails on a file
  with a shell shebang and another name. It reads a shebang that names
  `sh`, `bash`, `dash`, `ksh` or `zsh`, in any directory (`/bin`, a Nix
  store path, `/run/current-system/sw/bin`), directly or through `env` with
  options (`env -S bash -e`, `env -i bash`). It skips the argument of an
  `env` option that takes one (`-u NAME`, `-C DIR`, `-a NAME`, and their long
  forms), so `env -u NAME bash` is a Bash script and `env -u bash` is not.

The reason for `.sh`: treefmt, the treefmt-nix programs, EditorConfig
sections and editors select files by name only. A script without an
extension reaches no formatter and no linter unless someone lists it by
hand. The Google guide accepts both forms: "Executables should have a .sh
extension or no extension." Libraries "must have a .sh extension".

### Package managers

The organization uses pnpm only. The forbidden commands, files and
directories are the lists in [package-managers.nix](package-managers.nix).

- **The lint.** The `pnpm-only-lint` package fails (status 1) when a
  repository tracks a lock or configuration file of another package manager,
  or a `package.json` with a `packageManager` or `devEngines` field. Status 2
  means that the lint cannot check: a `package.json` that is not a regular
  file or a link to one (a dangling symlink), or not exactly one JSON object
  (an empty file, a second document, trailing text, `null`, an array); a
  failed file listing; or a usage error. In a Git work tree it reads
  the tracked files; elsewhere it reads every file except `.git` and
  `node_modules`. It runs only through its package, which sets the lists.
- **What the lint does not do.** It does not read commands. It does not
  detect `corepack`, `npm` or `npx` in a Dockerfile, a workflow or a script;
  `pnpm dlx`, `pnpm create` and `pnpm --silent dlx`; the Nix builders
  `buildNpmPackage` and `mkYarnPackage`; or `npx` on a hosted runner without
  Nix. A text scan cannot find a command in shell, YAML, Nix or a Dockerfile.
- **What enforces the rule for commands.** The PATH of the development shell:
  the commands of other package managers do not exist there.
  `lib.devShellPathCheck` builds the PATH of a shell with stdenv, so that
  propagated inputs, `inputsFrom` and the `bin` output count, and fails when a
  forbidden command is on it. It does not run `shellHook`, so a command that
  a hook adds to PATH is not found.

### YAML, JSON and Markdown

- Prettier formats them with its defaults and with `.editorconfig`. It keeps
  Markdown line breaks as written (`proseWrap: preserve`), because GitHub
  renders a single line break in a pull request or issue body as a break.
- yamllint runs its default rules, changed only where Prettier prints
  otherwise: one space inside `{ }`, one space before a comment, no
  `---` and no line length. GitHub's `on:` key is not read as a boolean.
  Every finding is an error.

### Workflows

- zizmor runs with the pedantic persona, offline, in the build sandbox. Its
  four online audits (`impostor-commit`, `known-vulnerable-actions`,
  `ref-confusion`, `stale-action-refs`) need the network and a GitHub token,
  so this check does not run them; a CI job with a token must.
- actionlint checks the `run:` scripts with ShellCheck. It calls ShellCheck
  with `--norc`, so the optional checks do not apply to `run:` scripts.

### Repository files that the tools read

- `.editorconfig` (required): shfmt, Prettier and `editorconfig-checker`
  read it.
- `_typos.toml`: the words that typos must accept, each with its reason.
- `.github/zizmor.yml` and `.github/actionlint.yaml`, when a repository
  needs them.

## Change it

1. Edit the files in this directory, and run `nix flake check` here.
2. A release is a tag `toolchain-vN` on `main`.
