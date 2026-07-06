<!--
SPDX-FileCopyrightText: The nix-devshell Authors
SPDX-License-Identifier: 0BSD
-->
# nix-devshell

The metio nix toolchain, in two halves:

- **A flake** (`lib.mkDevShell`) that assembles a repo's devShell from the
  shared lint gate (reuse, typos, yamllint, actionlint, shellcheck,
  markdownlint) and its `ci-*` command wrappers, plus the from-source Go tools
  nixpkgs does not ship (arch-go, modernize, helm-schema). Defined once here so
  every repo resolves the same tools from `flake.lock`.
- **A composite GitHub Action** that installs Nix and caches the `/nix` store,
  so a repo whose toolchain is that flake runs every CI gate through the
  devShell — identical to a local `nix develop`.

## Usage

Build the devShell from this flake, then in CI check the repo out, set Nix up
with the action, and run each gate through the devShell:

```nix
# flake.nix
inputs.devshell.url = "github:metio/nix-devshell";
inputs.nixpkgs.follows = "devshell/nixpkgs";
outputs = { nixpkgs, devshell, ... }: {
  devShells.<sys>.default = devshell.lib.mkDevShell {
    pkgs = nixpkgs.legacyPackages.<sys>;
    packages = [ /* repo-specific tools + gate commands */ ];
  };
};
```

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@<sha>
      - uses: metio/nix-devshell@<sha>
      - run: nix develop --command ci-reuse   # or any gate
```

The store is keyed on `flake.nix`/`flake.lock`, so it downloads the devShell
closure only when the flake pin changes; every other run restores it in seconds,
and a prefix fallback fetches only the delta after a lock bump. The two upstream
refs it pins — the Nix installer and the store cache — are Renovate-bumped like
any other action.

Pair it with the [`policy-check`](https://github.com/metio/ci#run-the-policies-in-another-repo)
flake rules, which require a flake repo's tools to come from the devShell rather
than setup or marketplace actions.

## License

[0BSD](LICENSES/0BSD.txt), REUSE-compliant.
