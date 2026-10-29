---
status: "accepted"
date: 2026-10-28
decision-makers: the code owners of this repository
---

# Enforce pnpm only without parsing commands

## Context and Problem Statement

The organization uses pnpm as its only Node package manager, and the
`package.json` files have no `packageManager` field. A repository must be able
to prove that no other package manager and no unpinned package runs. How does
a check find a use of `npm`, `npx`, `yarn`, `corepack` or `bun`?

A command can appear in a shell script, a workflow, a Nix expression or a
Dockerfile. A regular expression cannot find a command in shell: quoting,
`env`, variables and an absolute path hide it. A scan of text for command
names has false negatives that no one can count.

## Decision Drivers

- A check must test the repository, and must not guess what a shell does.
- A check must not fetch an unpinned package to run.
- The contract of the check must state what it does not detect.

## Considered Options

- A scan of the text of YAML, Nix, Dockerfiles and shell for forbidden
  commands.
- The `preinstall` script `npx only-allow pnpm`, which pnpm documents.
- A guard in three parts that parses nothing: file names, `package.json`
  fields and the environment.

## Decision Outcome

Chosen option: "A guard in three parts that parses nothing", because each part
checks a fact that a program can read without interpreting a language.

1. **File-name rule.** It reads `git ls-files -z`, the tracked files, which are
   also the files of the flake source. It fails on the lock and
   configuration files of other package managers: `package-lock.json`,
   `npm-shrinkwrap.json`, `yarn.lock`, `.yarnrc`, `.yarnrc.yml`, `.yarn/`,
   `.pnp.*`, `bun.lock*` and `bunfig.toml`.
2. **`package.json` rule.** One `jq` call fails on a `packageManager` or
   `devEngines` field. Malformed JSON ends the check with status 2.
3. **Environment.** The check of the development shell fails when `npm`,
   `npx`, `yarn`, `corepack` or `bun` is on the `PATH`. CI steps run inside
   the Nix shell, where these programs do not exist.

The exit status is 0 for a clean tree, 1 for findings and 2 when the check
cannot run. `toolchain/package-managers.nix` is the one list of names and
files. The toolchain README states what the guard does not detect: `corepack`
in a Dockerfile, and `npx` on a hosted runner outside Nix.

### Consequences

- Good, because the check has no regular expression over code, so a quoting
  trick cannot hide a command from it.
- Good, because the check fetches nothing.
- Bad, because a command in a Dockerfile or on a runner outside Nix is not
  detected.
- Bad, because the rule restricts the files and the environment, not the
  intent of the author.

### Confirmation

The flake runs the `pnpm-only` cases (every foreign file, an untracked file,
`packageManager`, `devEngines`, malformed JSON) and the `dev-shell-path` cases
(a direct input, a propagated input, an `inputsFrom` input and a clean shell).
The expected values are a hand-written list, not read from
`package-managers.nix`.

## Pros and Cons of the Options

### A scan of the text for forbidden commands

- Good, because it can find a command in a script.
- Bad, because shell has no regular grammar, and the scan misses `env`, an
  absolute path, a variable or a wrapper.
- Bad, because the scan flags the fixtures and the documents that name a
  command.

### The `preinstall` script `npx only-allow pnpm`

- Good, because it is the documented pnpm practice.
- Bad, because it fetches an unpinned package on every install.
- Bad, because it guards the `install` command only.

### A guard in three parts that parses nothing

- Good, because each part is deterministic.
- Bad, because it states a smaller contract, as the outcome lists.

## More Information

The toolchain README is the reference for the check.
