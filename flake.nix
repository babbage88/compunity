{
  description = "Go 1.26 + Vite React 19 SPA development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        go = if pkgs ? go_1_26 then pkgs.go_1_26 else pkgs.go;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            go
            gopls
            delve
            gotools
            go-tools
            golangci-lint
            sqlc
            goose

            nodejs_24
            pnpm
            yarn

            just
            jq
            curl
            git
            openssl
            postgresql
            sqlite
            air
            bash-completion
          ];

        shellHook = ''
          export GOPATH="$PWD/.nix-go"
          export GOBIN="$GOPATH/bin"
          export PATH="$GOBIN:$PATH"

          export PNPM_HOME="$PWD/.pnpm-home"
          export PATH="$PNPM_HOME:$PATH"

          mkdir -p "$GOPATH" "$GOBIN" "$PNPM_HOME"
          if [ -n "$BASH_VERSION" ]; then
            source ${pkgs.bash-completion}/etc/profile.d/bash_completion.sh
            eval "$(just --completions bash)"
            if command -v npm >/dev/null 2>&1; then
              source <(npm completion)
            fi
          
            if command -v pnpm >/dev/null 2>&1; then
              eval "$(pnpm completion bash)"
            fi
          fi
          # Pretty prompt
          RESET="\[\033[0m\]"
          BOLD="\[\033[1m\]"
          GREEN="\[\033[32m\]"
          CYAN="\[\033[36m\]"
          BLUE="\[\033[34m\]"
          export PS1="''${BOLD}''${GREEN}\u''${RESET}@''${CYAN}\h ''${BLUE}\w''${RESET} \\$ "

          for dir in */; do
          if [ -f "$dir/package.json" ]; then
              echo "Installing frontend deps in $dir"
              (
                cd "$dir"
                if [ -f pnpm-lock.yaml ]; then
                  pnpm install
                elif [ -f package-lock.json ]; then
                  npm ci
                elif [ -f yarn.lock ]; then
                  yarn install
                else
                  npm install
                fi
              )
            fi
          done
        
          echo "Dev shell ready"
          echo "Go:   $(go version)"
          echo "Node: $(node --version)"
          echo "npm:  $(npm --version)"
        '';
        };
      });
}