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
          # Use `:-` defaults so an externally-set value wins: on the host PGHOST
          # is localhost, but inside the devcontainer it's `postgres` (the sibling
          # compose service), set in .devcontainer/docker-compose.yml.
          shellHook = ''
            export PGHOST="''${PGHOST:-localhost}"
            export PGPORT="''${PGPORT:-5432}"
            export PGUSER="''${PGUSER:-graph}"
            export PGPASSWORD="''${PGPASSWORD:-graphpass}"
            export PGDATABASE="''${PGDATABASE:-graphlab}"
            echo "psql $(psql --version | awk '{print $3}') — connect with: psql"
            echo "  (targets postgres://$PGUSER@$PGHOST:$PGPORT/$PGDATABASE)"
          '';
        };
      });
    };
}
