{
  description = "Development inputs for secrets.nix";

  inputs = {
    nix-unit = {
      url = "github:nix-community/nix-unit";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
    };
  };

  outputs = _: {};
}
