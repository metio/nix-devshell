<!--
SPDX-FileCopyrightText: The nix-devshell Authors
SPDX-License-Identifier: 0BSD
-->
# nix-devshell

A composite GitHub Action that installs Nix and caches the `/nix` store, so a
repo whose toolchain is a nix flake runs every CI gate through the flake's
devShell and resolves the exact tool versions in `flake.lock` — identical to a
local `nix develop`.

## Usage

Check out the repo first, then run each gate with `nix develop --command …`:

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@<sha>
      - uses: metio/nix-devshell@<sha>
      - run: nix develop --command <gate>
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
