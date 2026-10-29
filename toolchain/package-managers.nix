# The JavaScript package managers other than pnpm: the one list that every
# pnpm-only rule reads. The organization uses pnpm only (toolchain/README.md).
#
# - `commands` is read by the development-shell PATH check
#   (dev-shell-path-check.nix), which fails when a shell puts one of them on
#   PATH.
# - `files` and `directories` are read by the pnpm-only lint
#   (pnpm-only-lint.sh), which fails when a repository tracks one of them.
#
# Returns: an attribute set of lists of strings.
{
  # Command names. `pnpx` and `pnx` are the aliases of `pnpm dlx` and are
  # forbidden because `pnpm dlx` runs a package that no lock file pins.
  commands = [
    "bun"
    "bunx"
    "corepack"
    "npm"
    "npx"
    "pnpx"
    "pnx"
    "yarn"
    "yarnpkg"
  ];

  # Shell glob patterns for the base name of a file that only another package
  # manager writes or reads: lock files and configuration.
  files = [
    "package-lock.json"
    "npm-shrinkwrap.json"
    "yarn.lock"
    ".yarnrc"
    ".yarnrc.yml"
    ".pnp.*"
    "bun.lock*"
    "bunfig.toml"
  ];

  # Names of directories that only another package manager writes (Yarn's
  # `.yarn/`). Any file below a directory of this name is foreign.
  directories = [ ".yarn" ];
}
