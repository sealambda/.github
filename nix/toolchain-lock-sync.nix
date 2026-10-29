# Builds a check that fails when the root flake.lock and toolchain/flake.lock
# lock different revisions of the toolchain's inputs.
#
# The root flake takes the toolchain as the relative input `path:./toolchain`
# and follows its nixpkgs. Nix copies toolchain/flake.lock into the root lock
# only when the root lock is created or `nix flake update toolchain` runs: a
# later update inside toolchain/ leaves the root lock behind, and Nix gives no
# warning. The two locks move in lock step: after any change of
# toolchain/flake.lock, run `nix flake update toolchain`. A tool that updates
# the locks automatically must update both in one change.
#
# Arguments (an attribute set):
#   `pkgs`: the nixpkgs package set.
#   `rootLock`: the parsed root flake.lock.
#   `toolchainLock`: the parsed toolchain/flake.lock.
# Returns: a derivation that builds when the locks agree. Its `disagreements`
#   attribute is the sorted list of the toolchain's input names whose locked
#   source differs; nix/toolchain-lock-sync-tests.nix tests it.
{
  pkgs,
  rootLock,
  toolchainLock,
}:
let
  inherit (pkgs) lib;

  # The node that an input reference names: a node name, or a `follows`
  # path of input names from the lock's root node.
  resolve =
    lock: reference:
    if builtins.isList reference then
      lib.foldl' (node: input: resolve lock lock.nodes.${node}.inputs.${input}) lock.root reference
    else
      reference;

  # The locked source of every input below a node, by input name, with
  # `follows` resolved; node names differ between the two locks.
  lockedInputs =
    lock: node:
    lib.mapAttrs (
      _: reference:
      let
        target = resolve lock reference;
      in
      {
        inherit (lock.nodes.${target}) locked;
        inputs = lockedInputs lock target;
      }
    ) (lock.nodes.${node}.inputs or { });

  # The toolchain's inputs as the root lock records them: below the node that
  # the root input `toolchain` names.
  inRoot = lockedInputs rootLock (resolve rootLock rootLock.nodes.${rootLock.root}.inputs.toolchain);

  # The toolchain's inputs as its own lock records them.
  inToolchain = lockedInputs toolchainLock toolchainLock.root;

  # The names of the inputs that the two locks lock differently, including an
  # input that only one of them has.
  disagreements = lib.filter (name: (inRoot.${name} or null) != (inToolchain.${name} or null)) (
    lib.attrNames (inRoot // inToolchain)
  );
in
pkgs.runCommandLocal "toolchain-lock-sync"
  {
    nativeBuildInputs = [ pkgs.jq ];
    passthru = { inherit disagreements; };
  }
  (
    if disagreements == [ ] then
      ''touch "$out"''
    else
      ''
        echo "flake.lock and toolchain/flake.lock lock different toolchain inputs: ${toString disagreements}" >&2
        echo "The locks move in lock step. Run: nix flake update toolchain" >&2
        echo "An update tool must update both locks in one change." >&2
        # One key per line, sorted, so that the diff shows the changed field.
        jq -S . ${builtins.toFile "toolchain.json" (builtins.toJSON inToolchain)} >toolchain.json
        jq -S . ${builtins.toFile "root.json" (builtins.toJSON inRoot)} >root.json
        diff -u toolchain.json root.json >&2 || true
        exit 1
      ''
  )
