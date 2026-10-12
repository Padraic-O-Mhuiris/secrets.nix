# secrets.nix - minimal secrets management module
{lib}: let
  inherit (lib) mkOption types;

  # Import module builders
  modulesLib = import ./modules.nix {inherit lib;};

  # Age public key regex pattern
  ageKeyPattern = "age1[a-z0-9]{58}";

  # Format to file extension mapping
  formatExtension = {
    bin = "";
    json = ".json";
    yaml = ".yaml";
    env = ".env";
  };

  # Recipient submodule
  recipientModule = {
    options = {
      key = mkOption {
        type = types.strMatching ageKeyPattern;
        description = "Public key for this recipient";
      };

      type = mkOption {
        type = types.enum ["age"];
        default = "age";
        readOnly = true; # Note only supporting age keys initially
        description = "Key type (sops backend)";
      };

      decryptPkg = mkOption {
        type = types.nullOr (types.functionTo types.package);
        default = null;
        description = "Function (pkgs -> drv) that produces the key command package for decryption";
      };
    };
  };

  # Secret submodule
  secretModule = {
    name,
    config,
    ...
  }: {
    options = {
      dir = mkOption {
        type = types.path;
        description = "Directory containing the encrypted secret file (relative to where it's declared)";
      };

      recipients = mkOption {
        type = types.attrsOf (types.submodule recipientModule);
        default = {};
        description = "Recipients who can decrypt this secret";
      };

      format = mkOption {
        type = types.enum ["bin" "json" "yaml" "env"];
        default = "bin";
        description = "Secret file format (used by sops for encryption/decryption)";
      };

      # Derived properties (read-only)
      _fileName = mkOption {
        type = types.str;
        readOnly = true;
        default = "${name}${formatExtension.${config.format}}";
        description = "Derived filename: <name><extension>";
      };

      _path = mkOption {
        type = types.path;
        readOnly = true;
        default = config.dir + "/${config._fileName}";
        description = "Derived full path: <dir>/<_fileName>";
      };

      _projectOutPath = mkOption {
        type = types.str;
        readOnly = true;
        default = let
          fullPath = toString config._path;
          storePrefix = builtins.storeDir + "/";
          # <hash>-source/<rest> -> <rest>
          relativeParts = lib.drop 1 (lib.splitString "/" (lib.removePrefix storePrefix fullPath));
        in
          if lib.hasPrefix storePrefix fullPath
          then "./" + lib.concatStringsSep "/" relativeParts
          else fullPath;
        description = "Path relative to the flake source root (./…), or the absolute path when dir is outside the Nix store";
      };

      _exists = mkOption {
        type = types.bool;
        readOnly = true;
        default = builtins.pathExists config._path;
        description = "Whether the secret file exists at the derived path";
      };

      # Package operations submodule
      __operations = mkOption {
        type = types.submodule (import ./operations {inherit lib name config;});
        internal = true;
        readOnly = true;
        default = {};
        description = "Package operation functions";
      };

      # sops-nix module builders
      mkNixosModule = mkOption {
        type = types.functionTo types.attrs;
        readOnly = true;
        default = modulesLib.mkNixosModule {
          inherit name;
          secretCfg = config;
        };
        description = "Build a NixOS module fragment for this secret";
      };

      mkHomeManagerModule = mkOption {
        type = types.functionTo types.attrs;
        readOnly = true;
        default = modulesLib.mkHomeManagerModule {
          inherit name;
          secretCfg = config;
        };
        description = "Build a Home-Manager module fragment for this secret";
      };

      mkDarwinModule = mkOption {
        type = types.functionTo types.attrs;
        readOnly = true;
        default = modulesLib.mkDarwinModule {
          inherit name;
          secretCfg = config;
        };
        description = "Build a Darwin module fragment for this secret";
      };
    };
  };

  inherit (import ./names.nix {inherit lib;}) namePattern toEnvVar;

  # Reserved names conflict with derivation attributes of the secrets package
  reservedNames = [
    "name"
    "meta"
    "passthru"
    "text"
    "type"
    "out"
    "outPath"
    "drvPath"
    "outputs"
    "outputName"
    "all"
    "args"
    "builder"
    "system"
    "overrideAttrs"
    "inputDerivation"
    "drvAttrs"
  ];

  # Names whose env var form collides, e.g. foo-bar and foo_bar
  envCollisions = names: let
    groups = lib.groupBy toEnvVar names;
  in
    lib.filter (g: builtins.length g > 1) (builtins.attrValues groups);

  showCollisions = gs: lib.concatMapStringsSep "; " (lib.concatStringsSep " / ") gs;

  # Check evaluated secrets; throws on the first problem, else returns them
  validateSecrets = secrets: let
    names = builtins.attrNames secrets;
    badNames = lib.filter (n: builtins.match namePattern n == null) names;
    reserved = lib.filter (n: builtins.elem n reservedNames) names;
    secretCollisions = envCollisions names;
    checkSecret = name: secret: let
      rNames = builtins.attrNames secret.recipients;
      badRecipients = lib.filter (n: builtins.match namePattern n == null) rNames;
      rCollisions = envCollisions rNames;
    in
      if rNames == []
      then throw "secrets.nix: secret '${name}' has no recipients; declare at least one in recipients"
      else if badRecipients != []
      then throw "secrets.nix: secret '${name}' has invalid recipient name(s): ${lib.concatStringsSep ", " badRecipients}. Names must match ${namePattern}"
      else if rCollisions != []
      then throw "secrets.nix: secret '${name}' has recipient names that map to the same environment variable: ${showCollisions rCollisions}"
      else secret;
  in
    if badNames != []
    then throw "secrets.nix: Invalid secret name(s): ${lib.concatStringsSep ", " badNames}. Names must match ${namePattern}"
    else if reserved != []
    then throw "secrets.nix: Invalid secret name(s): ${lib.concatStringsSep ", " reserved}. These names are reserved: ${lib.concatStringsSep ", " reservedNames}"
    else if secretCollisions != []
    then throw "secrets.nix: secret names that map to the same environment variable: ${showCollisions secretCollisions}"
    else lib.mapAttrs checkSecret secrets;
in {
  inherit secretModule validateSecrets;

  # Evaluate and validate a secrets configuration
  mkSecrets = secrets:
    validateSecrets (lib.mapAttrs (name: secretDef:
      (lib.evalModules {
        modules = [secretModule {config = secretDef;}];
        specialArgs = {inherit name;};
      })
      .config)
    secrets);

  # Create a "secrets" package with nested passthru
  mkSecretsPackages = import ./packages.nix {inherit lib;};
}
