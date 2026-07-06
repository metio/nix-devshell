# SPDX-FileCopyrightText: The nix-devshell Authors
# SPDX-License-Identifier: 0BSD

# This repo ships a composite action, not a toolchain — but it dogfoods that
# action in its own CI: verify.yml sets up Nix through `./` (this very action)
# and runs each lint gate with `nix develop --command …`. The devShell is the
# shared metio lint gate (reuse, typos, yamllint, actionlint, shellcheck,
# markdownlint) from ci.lib.mkDevShell, so a change to the action is checked by
# the action, and local and CI resolve the same tools from flake.lock.
{
  description = "The metio nix-devshell action, dogfooded through the shared lint gate";

  inputs = {
    ci.url = "github:metio/ci";
    nixpkgs.follows = "ci/nixpkgs";
  };

  outputs =
    { nixpkgs, ci, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = ci.lib.mkDevShell { inherit pkgs; };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
