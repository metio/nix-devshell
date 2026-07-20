# SPDX-FileCopyrightText: The nix-devshell Authors
# SPDX-License-Identifier: 0BSD

# The metio nix toolchain: the shared devShell (`lib.mkDevShell`) plus the from-
# source Go tools nixpkgs does not ship (arch-go, modernize, helm-schema), and —
# alongside this flake — the composite action (action.yml) that installs Nix in
# CI. Every metio repo builds its devShell from `lib.mkDevShell` and sets Nix up
# through this repo's action, so the lint gate (reuse, typos, yamllint, actionlint,
# shellcheck, markdownlint) and its `ci-*` command wrappers are defined once here
# instead of copied into each flake, and local and CI resolve the same tools from
# flake.lock. `update-flake.yml` keeps the from-source tools' versions + hashes
# current; a consuming repo picks the update up by bumping its `devshell` flake
# input (Renovate lock maintenance).
#
# A repo's flake becomes:
#
#   inputs.devshell.url = "github:metio/nix-devshell";
#   inputs.nixpkgs.follows = "devshell/nixpkgs";   # one nixpkgs pin, org-wide
#   outputs = { nixpkgs, devshell, ... }: {
#     devShells.<sys>.default = devshell.lib.mkDevShell {
#       pkgs = nixpkgs.legacyPackages.<sys>;
#       packages = [ … repo-specific tools + gate commands … ];
#       env.KUBEBUILDER_ASSETS = "${devshell.lib.kubebuilderAssets pkgs}";  # controllers only
#     };
#   };
#
# This repo dogfoods both halves: verify.yml installs Nix through `./` (its own
# action) and runs each lint gate via `nix develop --command ci-*` from the
# devShell this flake defines.
{
  description = "metio nix toolchain: the shared devShell, the Go tools nixpkgs lacks, and the Nix-installer action";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-compat.url = "github:edolstra/flake-compat";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # dadav/helm-schema (docs chart-values reference). Tags carry no `v`.
      helm-schema =
        pkgs:
        pkgs.buildGoModule rec {
          pname = "helm-schema";
          version = "0.23.4";
          src = pkgs.fetchFromGitHub {
            owner = "dadav";
            repo = "helm-schema";
            rev = version;
            hash = "sha256-btkkNzye9if4lF/YdhalbwA2/dcZArU6/9Hr0bTJf1M=";
          };
          vendorHash = "sha256-jbK+XD5CbjMQJUJCcKbNN8LhYuhuy+Z3XcCmgiYw25Y=";
        };

      # arch-go (architecture rules, arch-go.yml).
      arch-go =
        pkgs:
        pkgs.buildGoModule rec {
          pname = "arch-go";
          version = "2.1.2";
          src = pkgs.fetchFromGitHub {
            owner = "arch-go";
            repo = "arch-go";
            rev = "v${version}";
            hash = "sha256-clwVZ/5PwUiD1LzRG6jGghQWcWZP3Pj3CzrdZiHUrIQ=";
          };
          vendorHash = "sha256-xIf+Ty1Pqa3oqqFLFsOv8Jz2bLOaIF+kjfGao05FhrM=";
        };

      # modernize (newer-Go idiom check), a subpackage of x/tools' gopls module.
      modernize =
        pkgs:
        pkgs.buildGoModule rec {
          pname = "modernize";
          version = "0.48.0";
          src = pkgs.fetchFromGitHub {
            owner = "golang";
            repo = "tools";
            rev = "v${version}";
            hash = "sha256-4NhWECD/SMlPN4/Ubo4bWb1y57/biW2F0nS8fngOjTs=";
          };
          modRoot = "gopls";
          subPackages = [ "internal/analysis/modernize/cmd/modernize" ];
          vendorHash = "sha256-2LA1f20WNHdeOOee/xkTawIJmHh8XD4MA0QIF/7oqQg=";
        };

      # controller-runtime envtest wants a dir holding etcd, kube-apiserver, and
      # kubectl. Assemble it from nixpkgs so a controller's tests run offline
      # against the flake-pinned Kubernetes, no setup-envtest download.
      kubebuilderAssets =
        pkgs:
        pkgs.runCommand "kubebuilder-assets" { } ''
          mkdir -p $out
          ln -s ${pkgs.etcd}/bin/etcd $out/etcd
          ln -s ${pkgs.kubernetes}/bin/kube-apiserver $out/kube-apiserver
          ln -s ${pkgs.kubectl}/bin/kubectl $out/kubectl
        '';

      # The lint gate every metio repo shares, byte-for-byte.
      # harper comes from THIS flake's nixpkgs, not the caller's: older
      # stable channels package only harper-ls, and a consumer on 25.05
      # would otherwise get a ci-harper pointing at a binary that does
      # not exist. Everything else resolves against the caller's pkgs.
      harperFor =
        pkgs: nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.harper;

      lintTools =
        pkgs:
        (with pkgs; [
          reuse
          typos
          yamllint
          actionlint
          shellcheck # actionlint shells out to it for run: blocks
          markdownlint-cli2
        ])
        ++ [ (harperFor pkgs) ]; # grammar/style for prose; typos covers code

      # One canonical `ci-<tool>` command per shared lint tool, wrapping the EXACT
      # CI invocation (e.g. `reuse lint`, `yamllint .`). Defined
      # once here so every repo inherits them: a workflow runs the gate with
      # `nix develop --command ci-reuse`, and a developer runs the same name bare
      # inside `nix develop` — the invocation lives in one place instead of being
      # copied into each workflow's YAML and each repo's flake. The `ci-` prefix
      # leaves the raw tool free for its other modes (e.g. `reuse annotate`); the
      # wrapper pins only the CI mode. Tools are referenced by store path so the
      # wrapper resolves the flake-pinned binary regardless of PATH.
      lintCommands = pkgs: [
        (pkgs.writeShellScriptBin "ci-reuse" ''exec ${pkgs.reuse}/bin/reuse lint "$@"'')
        (pkgs.writeShellScriptBin "ci-typos" ''exec ${pkgs.typos}/bin/typos "$@"'')
        (pkgs.writeShellScriptBin "ci-yaml" ''exec ${pkgs.yamllint}/bin/yamllint . "$@"'')
        # actionlint finds shellcheck on PATH, which the devShell provides.
        (pkgs.writeShellScriptBin "ci-actionlint" ''exec ${pkgs.actionlint}/bin/actionlint "$@"'')
        # Lints the markdown the checkout tracks. A `**/*.md` glob reaches past
        # it into everything git ignores — vendored node_modules, mutation-test
        # sandboxes, fetched sources — so the gate passes in CI (a fresh
        # checkout has none of those) while a developer running it sees tens of
        # thousands of findings in files nobody in the repo wrote. A gate that
        # only works on a machine without dependencies installed is a gate
        # nobody runs before pushing. `git ls-files` is exactly what CI lints.
        # Explicit paths win, for linting one file while writing it.
        (pkgs.writeShellScriptBin "ci-markdown" ''
          set -eu
          if [ "$#" -gt 0 ]; then
            exec ${pkgs.markdownlint-cli2}/bin/markdownlint-cli2 "$@"
          fi
          if ${pkgs.git}/bin/git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            ${pkgs.git}/bin/git ls-files -z -- '*.md' '*.markdown' \
              | ${pkgs.findutils}/bin/xargs -0 -r ${pkgs.markdownlint-cli2}/bin/markdownlint-cli2
          else
            exec ${pkgs.markdownlint-cli2}/bin/markdownlint-cli2 "**/*.md"
          fi
        '')
        # harper lints PROSE (grammar, repeated words, style) where typos
        # lints CODE (identifier spelling) — complements, not substitutes,
        # so SpellCheck is off here; heading case is a style choice, so
        # UseTitleCase is off too. Repos append rules via HARPER_IGNORE.
        # Scope defaults to docs/ and kb/ (the prose homes); pass paths to
        # override. Exits non-zero via xargs when any file has findings.
        (pkgs.writeShellScriptBin "ci-harper" ''
          set -eu
          ignore="SpellCheck,UseTitleCase''\${HARPER_IGNORE:+,$HARPER_IGNORE}"
          if [ "$#" -gt 0 ]; then
            roots=("$@")
          else
            roots=()
            for d in docs kb; do [ -d "$d" ] && roots+=("$d"); done
            [ "''\${#roots[@]}" -gt 0 ] || roots=(.)
          fi
          ${pkgs.findutils}/bin/find "''\${roots[@]}" -name '*.md' -not -path './.git/*' -print0 \
            | ${pkgs.findutils}/bin/xargs -0 ${harperFor pkgs}/bin/harper-cli lint --ignore "$ignore"
        '')
      ];

      # Assemble a repo's devShell: the shared lint gate plus the repo's own
      # tools and gate commands, any extra env vars, its command menu, and any
      # always-run setup. `menu` prints only for an interactive shell — otherwise
      # it lands on the stdout that `nix develop --command <tool>` captures and
      # reads as tool output (e.g. golang.yml's gofumpt gate captures
      # `unformatted="$(… gofumpt -l .)"`). `shellHook` always runs.
      mkDevShell =
        {
          pkgs,
          packages ? [ ],
          env ? { },
          menu ? "",
          shellHook ? "",
        }:
        pkgs.mkShell (
          env
          // {
            packages = lintTools pkgs ++ lintCommands pkgs ++ packages;
            shellHook = ''
              if [ -t 1 ]; then
                echo "metio devshell — shared lint gate: reuse, typos, yamllint, actionlint, markdownlint-cli2, harper"
                echo "  run any the CI way: ci-reuse, ci-typos, ci-yaml, ci-actionlint, ci-markdown, ci-harper"
                ${menu}
              fi
            ''
            + shellHook;
          }
        );
    in
    {
      # System-independent building blocks a repo's flake composes.
      lib = {
        inherit
          mkDevShell
          lintTools
          lintCommands
          helm-schema
          arch-go
          modernize
          kubebuilderAssets
          ;
      };

      # The from-source packages, buildable for `nix build` and `nix-update`.
      packages = forAllSystems (pkgs: {
        helm-schema = helm-schema pkgs;
        arch-go = arch-go pkgs;
        modernize = modernize pkgs;
      });

      # This repo dogfoods its own shared devShell: the lint gate that verify.yml
      # runs through `nix develop --command ci-*`.
      devShells = forAllSystems (pkgs: {
        default = mkDevShell { inherit pkgs; };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
