{
  perSystem = { pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      packages = [
        pkgs.python312
        pkgs.uv
      ];
    };

    formatter = pkgs.nixfmt-tree;
  };
}
