{
  perSystem = { pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      packages = [ pkgs.uv ];
    };

    formatter = pkgs.nixfmt-tree;
  };
}
