# Visual Studio Code Server support in NixOS

Experimental support for VS Code Server in NixOS. The NodeJS by default supplied by VS Code cannot be used within NixOS due to missing hardcoded paths, so it is automatically replaced by a symlink to a compatible version of NodeJS that does work under NixOS.

## Installation

### Flake
```nix
1 {
 2   inputs = {
 3     nixpkgs.url = "nixpkgs/nixos-unstable";
 4     nixos-vscode-server.url ="github:tyler274/nixos-vscode-server/master";
 5   };
 6
 7   outputs = inputs@{ self, nixpkgs, ... }: {
 8     nixosConfigurations.Cassius = nixpkgs.lib.nixosSystem {
 9       system = "x86_64-linux";
10       modules = [
11         ./configuration.nix
12
13         # add things here
14         {
15             imports = [ inputs.nixos-vscode-server.nixosModules.system ];
16             services.vscode-server.enable = true;
17         }
18       ];
19
20     };
21   };
22 }
```

And then enable them for the relevant users:

```
systemctl --user enable auto-fix-vscode-server.service
```

You will see the following message:

```
The unit files have no installation config (WantedBy=, RequiredBy=, Also=,
Alias= settings in the [Install] section, and DefaultInstance= for template
units). This means they are not meant to be enabled using systemctl.
 
Possible reasons for having this kind of units are:
• A unit may be statically enabled by being symlinked from another unit's
  .wants/ or .requires/ directory.
• A unit's purpose may be to act as a helper for some other unit which has
  a requirement dependency on it.
• A unit may be started when needed via activation (socket, path, timer,
  D-Bus, udev, scripted systemctl call, ...).
• In case of template units, the unit is meant to be enabled with some
  instance name specified.
```

However you can safely ignore it. The service will start automatically after reboot once enabled, or you can just start it immediately yourself with:

```
systemctl --user start auto-fix-vscode-server.service
```

### Home Manager

Put this code into your [home-manager](https://github.com/nix-community/home-manager) configuration i.e. in `~/.config/nixpkgs/home.nix`:

```nix
{
    inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-vscode-server.url ="github:iosmanthus/nixos-vscode-server/add-flake";
  };

  outputs = inputs@{self, nixpkgs, ...}: {
    nixosConfigurations.some-host = nixpkgs.lib.nixosSystem rec {
        system = "x86_64-linux";
        # For more information of this field, check:
        # https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/eval-config.nix
        modules = [
          ./configuration.nix
          {
            home-manager = {
              user.iosmanthus = {
                imports = [ 
                  inputs.nixos-vscode-server.nixosModules.homeManager;
                ];
              };
            };
          }
        ];
      };
    };
}
```


When the service is enabled and running it should simply work, there is nothing for you to do.

## Known issues

This is not really an issue with this project per se, but with systemd user services in NixOS in general. After updating it can be necessary to first disable the service again:

```
systemctl --user disable auto-fix-vscode-server.service
````

This will remove the symlink to the old version. Then you can enable/start it again.
