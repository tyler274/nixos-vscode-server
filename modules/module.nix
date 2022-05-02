moduleConfig:
{ lib, pkgs, config, ... }:

with lib;

let
  originalNodePackage = pkgs.nodejs-16_x;

  # Adapted from https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/applications/editors/vscode/generic.nix#L181
  nodePackageFhs = pkgs.buildFHSUserEnv {
    name = originalNodePackage.name;

    # additional libraries which are commonly needed for extensions
    targetPkgs = pkgs: (with pkgs; [
      # ld-linux-x86-64-linux.so.2 and others
      glibc
      gdb

      # dotnet
      curl
      icu
      libunwind
      libuuid
      openssl
      zlib

      # mono
      krb5
    ]);

    runScript = "${originalNodePackage}/bin/node";

    meta = {
      description = ''
        Wrapped variant of ${name} which launches in an FHS compatible envrionment.
        Should allow for easy usage of extensions without nix-specific modifications.
      '';
    };
  };

  originalNodePackageBin = "${originalNodePackage}/bin/node";
  nodePackageFhsBin = "${nodePackageFhs}/bin/${nodePackageFhs.name}";

  nodeBinToUse = if 
    config.services.vscode-server.useFhsNodeEnvironment
  then 
    nodePackageFhsBin
  else
    originalNodePackageBin;
in
{
  options.services.vscode-server = {
    enable = with types; mkEnableOption "VS Code Server";

    useFhsNodeEnvironment = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Wraps NodeJS in a Fhs compatible envrionment. Should allow for easy usage of extensions without nix-specific modifications. 
      '';
    };
  };

  config = moduleConfig rec {
    name = "auto-fix-vscode-server";
    description = "Automatically fix the VS Code server used by the remote SSH extension";
    serviceConfig = {
      # When a monitored directory is deleted, it will stop being monitored.
      # Even if it is later recreated it will not restart monitoring it.
      # Unfortunately the monitor does not kill itself when it stops monitoring,
      # so rather than creating our own restart mechanism, we leverage systemd to do this for us.
      Restart = "always";
      RestartSec = 0;
      ExecStart = "${pkgs.writeShellScript "${name}.sh" ''
        set -euo pipefail
        PATH=${makeBinPath (with pkgs; [ coreutils findutils inotify-tools ])}
        bin_dir=~/.vscode-server/bin
        interpreter=$(patchelf --print-interpreter /run/current-system/sw/bin/sh)

        # Fix any existing symlinks before we enter the inotify loop.
        if [[ -e $bin_dir ]]; then
          find "$bin_dir" -mindepth 2 -maxdepth 2 -name node -exec ln -sfT ${nodeBinToUse} {} \;          
          find "$bin_dir" -path '*/@vscode/ripgrep/bin/rg' -exec ln -sfT ${pkgs.ripgrep}/bin/rg {} \;

        else
          mkdir -p "$bin_dir"
        fi

        for i in ~/.vscode-server/extensions/ms-vscode.*/bin/cpptools*; do
          patchelf --set-interpreter "$interpreter" "$i"
        done

        while IFS=: read -r bin_dir event; do
          # A new version of the VS Code Server is being created.
          if [[ $event == 'CREATE,ISDIR' ]]; then
            # Create a trigger to know when their node is being created and replace it for our symlink.
            touch "$bin_dir/node"
            inotifywait -qq -e DELETE_SELF "$bin_dir/node"
            ln -sfT ${nodeBinToUse} "$bin_dir/node"
            ln -sfT ${pkgs.ripgrep}/bin/rg "$bin_dir/node_modules/@vscode/ripgrep/bin/rg"
            for i in ~/.vscode-server/extensions/ms-vscode.*/bin/cpptools*; do
        patchelf --set-interpreter "$interpreter" "$i"
            done
          # The monitored directory is deleted, e.g. when "Uninstall VS Code Server from Host" has been run.
          elif [[ $event == DELETE_SELF ]]; then
            # See the comments above Restart in the service config.
            exit 0
          fi
        done < <(inotifywait -q -m -e CREATE,ISDIR -e DELETE_SELF --format '%w%f:%e' "$bin_dir")
      ''}";
    };
  };
}
