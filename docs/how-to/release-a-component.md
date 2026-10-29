# Release a component

Publish a new version of a component of this repository: the toolchain
(`toolchain-vN`) or the docs kit (`docs-kit-vN`). This guide is the only place
that describes a release for every component. Follow it when a change is on
`main` and consumers must be able to take it.

## Before you start

- The change is on `main`, and `nix flake check` passes on that commit. The
  check `lock-sync` fails until the lock files of `toolchain/`, `docs-kit/` and
  the root agree. If it fails, update them from the bottom up:

  ```bash
  (cd docs-kit && nix flake update toolchain)
  nix flake update toolchain docs-kit
  ```

  A consumer of a tag reads the lock file of the component, not the lock file
  of the root.

- You can push tags to the repository and create releases with `gh`.

## Steps

1. Choose `N` for the component. It is a whole number, one more than the
   highest existing tag of that component. The first release is 1.

   ```bash
   git tag --list 'docs-kit-v*' --sort=-version:refname | head -n 1
   ```

2. Tag the commit on `main` and push the tag:

   ```bash
   git tag -a docs-kit-vN -m "docs-kit-vN" <commit>
   git push origin docs-kit-vN
   ```

3. For the docs kit, build the Vale package from the tag. The toolchain has no
   asset, so skip this step for it.

   ```bash
   nix build "github:sealambda/.github?dir=docs-kit&ref=docs-kit-vN#vale-package"
   ```

   The file is `result/Sealambda.zip`.

4. Create the release. GitHub writes the notes from the merged pull requests
   between the previous tag of the same component and the new tag. The
   categories are in [`.github/release.yml`](../../.github/release.yml).
   `docs-kit-vM` is the previous tag of the component. For the first release of
   a component, leave out `--notes-start-tag`.

   ```bash
   gh release create docs-kit-vN result/Sealambda.zip \
     --title docs-kit-vN --verify-tag --generate-notes \
     --notes-start-tag docs-kit-vM
   ```

   The release of the toolchain has no asset:

   ```bash
   gh release create toolchain-vN \
     --title toolchain-vN --verify-tag --generate-notes \
     --notes-start-tag toolchain-vM
   ```

5. In each consumer, change the tag in the flake input, and for the docs kit
   also the `Packages` URL in `.vale.ini` and the `uses:` line of the workflow.
   Then run `nix flake update docs-kit`, or `nix flake update toolchain`.

## Check the result

- `gh release view docs-kit-vN` shows the notes and, for the docs kit, the
  asset `Sealambda.zip`.
- In a consumer, `nix flake check` passes with the new tag.

## If a step fails

- A tag that points at the wrong commit is never moved or deleted. Publish the
  next number with the fix, and say in its notes that the old number is void.
- The release notes list every pull request merged between the two tags, of any
  component. Edit the notes in the release before you announce it if pull
  requests of another component appear.

## Related

- [Use the docs kit](use-the-docs-kit.md): how a consumer takes a release.
- [Docs kit](../../docs-kit/README.md): the reference for the outputs of the
  kit and the rules for `N`.
