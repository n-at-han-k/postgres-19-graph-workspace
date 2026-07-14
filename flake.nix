{
  description = "psql client shell for the pg19-graph workspace";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.postgresql_17 ];

          # Matches docker-compose.yaml / .env — so a bare `psql` just connects.
          PGHOST = "localhost";
          PGPORT = "5432";
          PGUSER = "graph";
          PGPASSWORD = "graphpass";
          PGDATABASE = "graphlab";

          shellHook = ''
            echo "psql $(psql --version | awk '{print $3}') — connect with: psql"
            echo "  (targets postgres://graph@localhost:5432/graphlab)"
          '';
        };
      });
    };
}
