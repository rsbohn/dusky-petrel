{
  description = "Dusky Petrel - Data General Nova 1210 emulator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          dotnet = pkgs.dotnetCorePackages;
        in
        {
          default = dotnet.buildDotnetModule {
            pname = "dusky-petrel";
            version = "0.1.0";
            src = self;

            projectFile = "dusky/Snova.csproj";
            nugetDeps = [ ];

            dotnet-sdk = dotnet.sdk_9_0;
            dotnet-runtime = dotnet.runtime_9_0;

            executables = [ "Snova" ];
            doCheck = false;

            meta = {
              description = "Minimal Data General Nova 1210 emulator with monitor and assembler";
              mainProgram = "Snova";
            };
          };
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/Snova";
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.dotnetCorePackages.sdk_9_0 pkgs.gh ];
          };
        });
    };
}
