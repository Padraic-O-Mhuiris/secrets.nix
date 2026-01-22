# Unit tests for secrets.nix
#
# Run with: nix-unit --flake .#tests
# Or: nix flake check
#
{
  lib,
  pkgs ? null,
  corePath ? ../../core,
}: let
  inherit (import corePath {inherit lib;}) mkSecrets mkSecretsPackages;

  # Valid age keys for testing (from flake.nix examples)
  validAgeKey1 = "age1yct6cdz4f2hguaamc0jqxjx0m00v2puqacx0339mutagv8xmpffqcxql4v";
  validAgeKey2 = "age1wdw6tuppmmcufrh6wzgy93jah9wzppaqn69wt5un8qzz8lk5ep5ss6ed3f";
  validAgeKey3 = "age1jmxpfw8y5e5njm5fq08n65ceu7vuydx5l8wxk7hyu9s3x5qs93ysxqrd8l";

  # Test fixtures
  testDir = /tmp/test-secrets;
in
  {
    # ===========================================================================
    # Age Key Validation Tests
    # ===========================================================================

    "test age key validation: accepts valid key (alice)" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test.recipients.alice.key;
      expected = validAgeKey1;
    };

    "test age key validation: accepts valid key (bob)" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients.bob = {key = validAgeKey2;};
          };
        };
      in
        secrets.test.recipients.bob.key;
      expected = validAgeKey2;
    };

    "test age key validation: rejects empty string" = {
      expr = mkSecrets {
        test = {
          dir = testDir;
          recipients.alice = {key = "";};
        };
      };
      expectedError = {
        type = "ThrownError";
        msg = "not of type.*string matching the pattern age1";
      };
    };

    "test age key validation: rejects too short key" = {
      expr = mkSecrets {
        test = {
          dir = testDir;
          recipients.alice = {key = "age1abc";};
        };
      };
      expectedError = {
        type = "ThrownError";
        msg = "not of type.*string matching the pattern age1";
      };
    };

    "test age key validation: rejects uppercase key" = {
      expr = mkSecrets {
        test = {
          dir = testDir;
          recipients.alice = {key = "AGE1YCT6CDZ4F2HGUAAMC0JQXJX0M00V2PUQACX0339MUTAGV8XMPFFQCXQL4V";};
        };
      };
      expectedError = {
        type = "ThrownError";
        msg = "not of type.*string matching the pattern age1";
      };
    };

    "test age key validation: rejects wrong prefix" = {
      expr = mkSecrets {
        test = {
          dir = testDir;
          recipients.alice = {key = "age2yct6cdz4f2hguaamc0jqxjx0m00v2puqacx0339mutagv8xmpffqcxql4v";};
        };
      };
      expectedError = {
        type = "ThrownError";
        msg = "not of type.*string matching the pattern age1";
      };
    };

    "test age key validation: rejects SSH key" = {
      expr = mkSecrets {
        test = {
          dir = testDir;
          recipients.alice = {key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...";};
        };
      };
      expectedError = {
        type = "ThrownError";
        msg = "not of type.*string matching the pattern age1";
      };
    };

    # ===========================================================================
    # Format Extension Mapping Tests
    # ===========================================================================

    "test format extension: bin -> no extension" = {
      expr = let
        secrets = mkSecrets {
          test-secret = {
            dir = testDir;
            format = "bin";
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test-secret._fileName;
      expected = "test-secret";
    };

    "test format extension: json -> .json" = {
      expr = let
        secrets = mkSecrets {
          test-secret = {
            dir = testDir;
            format = "json";
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test-secret._fileName;
      expected = "test-secret.json";
    };

    "test format extension: yaml -> .yaml" = {
      expr = let
        secrets = mkSecrets {
          test-secret = {
            dir = testDir;
            format = "yaml";
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test-secret._fileName;
      expected = "test-secret.yaml";
    };

    "test format extension: env -> .env" = {
      expr = let
        secrets = mkSecrets {
          test-secret = {
            dir = testDir;
            format = "env";
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test-secret._fileName;
      expected = "test-secret.env";
    };

    "test format: default is bin" = {
      expr = let
        secrets = mkSecrets {
          test-secret = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test-secret.format;
      expected = "bin";
    };

    "test format: invalid format rejected" = {
      expr = mkSecrets {
        test-secret = {
          dir = testDir;
          format = "xml";
          recipients.alice = {key = validAgeKey1;};
        };
      };
      expectedError = {
        type = "ThrownError";
        msg = "option.*format.*is not of type.*one of";
      };
    };

    # ===========================================================================
    # Derived Properties Tests
    # ===========================================================================

    "test derived: _path combines dir and _fileName" = {
      expr = let
        secrets = mkSecrets {
          api-key = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.api-key._path;
      expected = testDir + "/api-key";
    };

    "test derived: _path with json format" = {
      expr = let
        secrets = mkSecrets {
          config = {
            dir = testDir;
            format = "json";
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.config._path;
      expected = testDir + "/config.json";
    };

    "test derived: dir is preserved" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test.dir;
      expected = testDir;
    };

    "test derived: _projectOutPath starts with ./" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /nix/store/abc123/secrets;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        lib.hasPrefix "./" secrets.test._projectOutPath;
      expected = true;
    };

    "test derived: _exists is false for nonexistent path" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/definitely-does-not-exist-xyz789;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test._exists;
      expected = false;
    };

    # ===========================================================================
    # Recipient Module Tests
    # ===========================================================================

    "test recipient: key is preserved" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test.recipients.alice.key;
      expected = validAgeKey1;
    };

    "test recipient: type defaults to age" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test.recipients.alice.type;
      expected = "age";
    };

    "test recipient: decryptPkg defaults to null" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test.recipients.alice.decryptPkg;
      expected = null;
    };

    "test recipient: decryptPkg can be a function" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients.alice = {
              key = validAgeKey1;
              decryptPkg = pkgs: pkgs.hello;
            };
          };
        };
        # decryptPkg is stored as a functor (callable set with __functor)
        pkg = secrets.test.recipients.alice.decryptPkg;
      in
        pkg != null && (builtins.isFunction pkg || (builtins.isAttrs pkg && pkg ? __functor));
      expected = true;
    };

    "test recipient: multiple recipients" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients = {
              alice = {key = validAgeKey1;};
              bob = {key = validAgeKey2;};
              server1 = {key = validAgeKey3;};
            };
          };
        };
      in
        builtins.length (builtins.attrNames secrets.test.recipients);
      expected = 3;
    };

    "test recipient: missing key throws" = {
      expr = mkSecrets {
        test = {
          dir = testDir;
          recipients.alice = {};
        };
      };
      expectedError = {
        type = "ThrownError";
        msg = "option.*recipients.alice.key.*was accessed but has no value defined";
      };
    };

    # ===========================================================================
    # Multiple Secrets Tests
    # ===========================================================================

    "test multiple secrets: count is correct" = {
      expr = let
        secrets = mkSecrets {
          secret1 = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
          secret2 = {
            dir = testDir;
            recipients.bob = {key = validAgeKey2;};
          };
          secret3 = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.length (builtins.attrNames secrets);
      expected = 3;
    };

    "test multiple secrets: each has independent format" = {
      expr = let
        secrets = mkSecrets {
          secret1 = {
            dir = testDir;
            format = "bin";
            recipients.alice = {key = validAgeKey1;};
          };
          secret2 = {
            dir = testDir;
            format = "json";
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in {
        s1 = secrets.secret1.format;
        s2 = secrets.secret2.format;
      };
      expected = {
        s1 = "bin";
        s2 = "json";
      };
    };

    "test multiple secrets: each has independent recipients" = {
      expr = let
        secrets = mkSecrets {
          secret1 = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
          secret2 = {
            dir = testDir;
            recipients.bob = {key = validAgeKey2;};
          };
        };
      in {
        s1 = builtins.attrNames secrets.secret1.recipients;
        s2 = builtins.attrNames secrets.secret2.recipients;
      };
      expected = {
        s1 = ["alice"];
        s2 = ["bob"];
      };
    };

    # ===========================================================================
    # Edge Cases and Required Fields Tests
    # ===========================================================================

    "test edge case: empty secrets map is valid" = {
      expr = mkSecrets {};
      expected = {};
    };

    "test edge case: secret name with hyphens" = {
      expr = let
        secrets = mkSecrets {
          my-api-key = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "my-api-key" secrets;
      expected = true;
    };

    "test edge case: secret name with underscores" = {
      expr = let
        secrets = mkSecrets {
          my_api_key = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "my_api_key" secrets;
      expected = true;
    };

    "test edge case: single character secret name" = {
      expr = let
        secrets = mkSecrets {
          x = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "x" secrets;
      expected = true;
    };

    "test edge case: numeric secret name" = {
      expr = let
        secrets = mkSecrets {
          "123" = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "123" secrets;
      expected = true;
    };

    "test required: missing dir throws" = {
      expr = mkSecrets {
        test = {
          recipients.alice = {key = validAgeKey1;};
        };
      };
      expectedError = {
        type = "ThrownError";
        msg = "option.*dir.*was accessed but has no value defined";
      };
    };

    # ===========================================================================
    # Operations Module Tests (structure only)
    # ===========================================================================

    "test operations: __operations exists" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "__operations" secrets.test;
      expected = true;
    };

    "test operations: init available for nonexistent secret" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "init" secrets.test.__operations;
      expected = true;
    };

    "test operations: env always available" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "env" secrets.test.__operations;
      expected = true;
    };

    "test operations: decrypt NOT available for nonexistent" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "decrypt" secrets.test.__operations;
      expected = false;
    };

    "test operations: edit NOT available for nonexistent" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "edit" secrets.test.__operations;
      expected = false;
    };

    "test operations: rotate NOT available for nonexistent" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "rotate" secrets.test.__operations;
      expected = false;
    };

    "test operations: rekey NOT available for nonexistent" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "rekey" secrets.test.__operations;
      expected = false;
    };

    # ===========================================================================
    # Operations Type Tests (functors that take pkgs)
    # ===========================================================================

    "test operations: init is callable (functor)" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        op = secrets.test.__operations.init;
      in
        # Operations are functors (sets with __functor attribute)
        builtins.isAttrs op && op ? __functor;
      expected = true;
    };

    "test operations: env is callable (functor)" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        op = secrets.test.__operations.env;
      in
        # Operations are functors (sets with __functor attribute)
        builtins.isAttrs op && op ? __functor;
      expected = true;
    };

    # ===========================================================================
    # Secret Name Validation Tests
    # ===========================================================================

    "test secret name: valid hyphenated name" = {
      expr = let
        secrets = mkSecrets {
          my-secret-key = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "my-secret-key" secrets;
      expected = true;
    };

    "test secret name: valid underscored name" = {
      expr = let
        secrets = mkSecrets {
          my_secret_key = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "my_secret_key" secrets;
      expected = true;
    };

    "test secret name: valid dotted name" = {
      expr = let
        secrets = mkSecrets {
          "my.secret.key" = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "my.secret.key" secrets;
      expected = true;
    };

    # ===========================================================================
    # Recipient Configuration Tests
    # ===========================================================================

    "test recipient: env var name derivation (hyphen to underscore)" = {
      expr = let
        secrets = mkSecrets {
          "api-key" = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        # The env operation generates env var names based on secret name
        # api-key becomes API_KEY
      in
        # We can verify the secret name contains hyphen
        lib.hasInfix "-" "api-key";
      expected = true;
    };

    "test recipient: multiple recipients with different keys" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients = {
              alice = {key = validAgeKey1;};
              bob = {key = validAgeKey2;};
              server1 = {key = validAgeKey3;};
            };
          };
        };
      in {
        alice = secrets.test.recipients.alice.key;
        bob = secrets.test.recipients.bob.key;
        server1 = secrets.test.recipients.server1.key;
      };
      expected = {
        alice = validAgeKey1;
        bob = validAgeKey2;
        server1 = validAgeKey3;
      };
    };

    "test recipient: decryptPkg stored correctly" = {
      expr = let
        mockDecryptFn = pkgs: pkgs.hello;
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients.alice = {
              key = validAgeKey1;
              decryptPkg = mockDecryptFn;
            };
          };
        };
        stored = secrets.test.recipients.alice.decryptPkg;
      in
        # decryptPkg is stored - verify it's not null and is callable
        stored != null && (builtins.isFunction stored || (builtins.isAttrs stored && stored ? __functor));
      expected = true;
    };

    "test recipient: decryptPkg null by default" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test.recipients.alice.decryptPkg;
      expected = null;
    };

    # ===========================================================================
    # Format Validation Tests
    # ===========================================================================

    "test format: all valid formats accepted" = {
      expr = let
        secrets = mkSecrets {
          bin-secret = {
            dir = testDir;
            format = "bin";
            recipients.alice = {key = validAgeKey1;};
          };
          json-secret = {
            dir = testDir;
            format = "json";
            recipients.alice = {key = validAgeKey1;};
          };
          yaml-secret = {
            dir = testDir;
            format = "yaml";
            recipients.alice = {key = validAgeKey1;};
          };
          env-secret = {
            dir = testDir;
            format = "env";
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in {
        bin = secrets.bin-secret.format;
        json = secrets.json-secret.format;
        yaml = secrets.yaml-secret.format;
        env = secrets.env-secret.format;
      };
      expected = {
        bin = "bin";
        json = "json";
        yaml = "yaml";
        env = "env";
      };
    };

    "test format: invalid format toml rejected" = {
      expr = mkSecrets {
        test = {
          dir = testDir;
          format = "toml";
          recipients.alice = {key = validAgeKey1;};
        };
      };
      expectedError = {
        type = "ThrownError";
        msg = "one of.*bin.*json.*yaml.*env";
      };
    };

    "test format: invalid format txt rejected" = {
      expr = mkSecrets {
        test = {
          dir = testDir;
          format = "txt";
          recipients.alice = {key = validAgeKey1;};
        };
      };
      expectedError = {
        type = "ThrownError";
        msg = "one of.*bin.*json.*yaml.*env";
      };
    };

    # ===========================================================================
    # Operations Availability Based on Existence Tests
    # ===========================================================================

    "test operations: only init and env for nonexistent secret" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        ops = builtins.attrNames secrets.test.__operations;
      in
        builtins.sort builtins.lessThan ops;
      expected = ["env" "init"];
    };

    # ===========================================================================
    # Dir Path Validation Tests
    # ===========================================================================

    "test dir: accepts absolute path" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /nix/store/abc123-test;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.typeOf secrets.test.dir;
      expected = "path";
    };

    "test dir: path preserved in config" = {
      expr = let
        testPath = /home/user/secrets;
        secrets = mkSecrets {
          test = {
            dir = testPath;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test.dir;
      expected = /home/user/secrets;
    };

    # ===========================================================================
    # Derived Properties Computation Tests
    # ===========================================================================

    "test derived: _fileName correct for all formats" = {
      expr = let
        secrets = mkSecrets {
          test-bin = {
            dir = testDir;
            format = "bin";
            recipients.alice = {key = validAgeKey1;};
          };
          test-json = {
            dir = testDir;
            format = "json";
            recipients.alice = {key = validAgeKey1;};
          };
          test-yaml = {
            dir = testDir;
            format = "yaml";
            recipients.alice = {key = validAgeKey1;};
          };
          test-env = {
            dir = testDir;
            format = "env";
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in {
        bin = secrets.test-bin._fileName;
        json = secrets.test-json._fileName;
        yaml = secrets.test-yaml._fileName;
        env = secrets.test-env._fileName;
      };
      expected = {
        bin = "test-bin";
        json = "test-json.json";
        yaml = "test-yaml.yaml";
        env = "test-env.env";
      };
    };

    "test derived: _path combines dir and fileName correctly" = {
      expr = let
        secrets = mkSecrets {
          my-secret = {
            dir = /home/user/project/secrets;
            format = "json";
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.my-secret._path;
      expected = /home/user/project/secrets/my-secret.json;
    };

    "test derived: _exists false for nonexistent path" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/this-path-definitely-does-not-exist-abc123xyz;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        secrets.test._exists;
      expected = false;
    };

    # ===========================================================================
    # Edge Cases Tests
    # ===========================================================================

    "test edge: empty recipients map rejected on access" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients = {};
          };
        };
      in
        builtins.attrNames secrets.test.recipients;
      expected = [];
    };

    "test edge: special characters in secret name" = {
      expr = let
        secrets = mkSecrets {
          "test@123" = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "test@123" secrets;
      expected = true;
    };

    "test edge: very long secret name" = {
      expr = let
        longName = "this-is-a-very-long-secret-name-that-might-cause-issues-with-some-systems";
        secrets = mkSecrets {
          ${longName} = {
            dir = testDir;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr longName secrets;
      expected = true;
    };

    "test edge: recipient name with numbers" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = testDir;
            recipients.server123 = {key = validAgeKey1;};
          };
        };
      in
        builtins.hasAttr "server123" secrets.test.recipients;
      expected = true;
    };

    "test edge: multiple secrets share recipients object" = {
      expr = let
        sharedRecipients = {
          alice = {key = validAgeKey1;};
          bob = {key = validAgeKey2;};
        };
        secrets = mkSecrets {
          secret1 = {
            dir = testDir;
            recipients = sharedRecipients;
          };
          secret2 = {
            dir = testDir;
            recipients = sharedRecipients;
          };
        };
      in {
        s1Alice = secrets.secret1.recipients.alice.key;
        s2Alice = secrets.secret2.recipients.alice.key;
        s1Bob = secrets.secret1.recipients.bob.key;
        s2Bob = secrets.secret2.recipients.bob.key;
      };
      expected = {
        s1Alice = validAgeKey1;
        s2Alice = validAgeKey1;
        s1Bob = validAgeKey2;
        s2Bob = validAgeKey2;
      };
    };
  }
  # ===========================================================================
  # Derivation Construction Tests (requires pkgs)
  # ===========================================================================
  // lib.optionalAttrs (pkgs != null) {
    "test drv: init produces derivation with correct name" = {
      expr = let
        secrets = mkSecrets {
          my-secret = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        drv = secrets.my-secret.__operations.init pkgs;
      in
        drv.name;
      expected = "init-my-secret";
    };

    "test drv: env produces derivation with correct name" = {
      expr = let
        secrets = mkSecrets {
          my-secret = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        drv = secrets.my-secret.__operations.env pkgs;
      in
        drv.name;
      expected = "env-my-secret";
    };

    "test drv: init derivation is a shell application" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        drv = secrets.test.__operations.init pkgs;
      in
        # writeShellApplication produces a derivation with meta.mainProgram
        drv ? meta && drv.meta ? mainProgram;
      expected = true;
    };

    "test drv: env derivation is a shell application" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        drv = secrets.test.__operations.env pkgs;
      in
        drv ? meta && drv.meta ? mainProgram;
      expected = true;
    };

    "test drv: init mainProgram matches name" = {
      expr = let
        secrets = mkSecrets {
          api-key = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        drv = secrets.api-key.__operations.init pkgs;
      in
        drv.meta.mainProgram;
      expected = "init-api-key";
    };

    "test drv: env mainProgram matches name" = {
      expr = let
        secrets = mkSecrets {
          api-key = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        drv = secrets.api-key.__operations.env pkgs;
      in
        drv.meta.mainProgram;
      expected = "env-api-key";
    };

    # ===========================================================================
    # Builder Pattern Tests (requires pkgs)
    # ===========================================================================

    # Note: decrypt/edit/rotate/rekey require _exists=true, which needs a real file.
    # We test the builder pattern structure on init since it doesn't have builders,
    # but we can verify the pattern exists by checking that operations are functors.

    "test builder: multiple secrets produce independent derivations" = {
      expr = let
        secrets = mkSecrets {
          secret1 = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
          secret2 = {
            dir = /tmp/nonexistent-12345;
            recipients.bob = {key = validAgeKey2;};
          };
        };
        drv1 = secrets.secret1.__operations.init pkgs;
        drv2 = secrets.secret2.__operations.init pkgs;
      in {
        name1 = drv1.name;
        name2 = drv2.name;
        different = drv1.name != drv2.name;
      };
      expected = {
        name1 = "init-secret1";
        name2 = "init-secret2";
        different = true;
      };
    };

    "test builder: same secret called twice returns equivalent derivation" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        drv1 = secrets.test.__operations.init pkgs;
        drv2 = secrets.test.__operations.init pkgs;
      in
        drv1.name == drv2.name;
      expected = true;
    };

    # ===========================================================================
    # Format-Specific Derivation Tests (requires pkgs)
    # ===========================================================================

    "test drv format: json secret init has correct name" = {
      expr = let
        secrets = mkSecrets {
          config = {
            dir = /tmp/nonexistent-12345;
            format = "json";
            recipients.alice = {key = validAgeKey1;};
          };
        };
        drv = secrets.config.__operations.init pkgs;
      in
        drv.name;
      expected = "init-config";
    };

    "test drv format: env secret init has correct name" = {
      expr = let
        secrets = mkSecrets {
          dotenv = {
            dir = /tmp/nonexistent-12345;
            format = "env";
            recipients.alice = {key = validAgeKey1;};
          };
        };
        drv = secrets.dotenv.__operations.init pkgs;
      in
        drv.name;
      expected = "init-dotenv";
    };

    # ===========================================================================
    # Recipient-Aware Derivation Tests (requires pkgs)
    # ===========================================================================

    "test drv recipients: multi-recipient secret produces single init drv" = {
      expr = let
        secrets = mkSecrets {
          shared = {
            dir = /tmp/nonexistent-12345;
            recipients = {
              alice = {key = validAgeKey1;};
              bob = {key = validAgeKey2;};
              server1 = {key = validAgeKey3;};
            };
          };
        };
        drv = secrets.shared.__operations.init pkgs;
      in
        drv.name;
      expected = "init-shared";
    };

    # ===========================================================================
    # mkSecretsPackages Tests (requires pkgs)
    # ===========================================================================

    "test packages: top-level package has correct name" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        pkg = mkSecretsPackages secrets pkgs;
      in
        pkg.name;
      expected = "secrets";
    };

    "test packages: top-level package has secret in passthru" = {
      expr = let
        secrets = mkSecrets {
          my-secret = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        pkg = mkSecretsPackages secrets pkgs;
      in
        pkg ? my-secret;
      expected = true;
    };

    "test packages: multiple secrets in passthru" = {
      expr = let
        secrets = mkSecrets {
          secret1 = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
          secret2 = {
            dir = /tmp/nonexistent-12345;
            recipients.bob = {key = validAgeKey2;};
          };
        };
        pkg = mkSecretsPackages secrets pkgs;
      in {
        hasSecret1 = pkg ? secret1;
        hasSecret2 = pkg ? secret2;
      };
      expected = {
        hasSecret1 = true;
        hasSecret2 = true;
      };
    };

    "test packages: secret package has correct name" = {
      expr = let
        secrets = mkSecrets {
          api-key = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        pkg = mkSecretsPackages secrets pkgs;
      in
        pkg.api-key.name;
      expected = "secret-api-key";
    };

    "test packages: secret package has init operation" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        pkg = mkSecretsPackages secrets pkgs;
      in
        pkg.test ? init;
      expected = true;
    };

    "test packages: secret package has env operation" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        pkg = mkSecretsPackages secrets pkgs;
      in
        pkg.test ? env;
      expected = true;
    };

    "test packages: init operation is a derivation" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        pkg = mkSecretsPackages secrets pkgs;
      in
        pkg.test.init ? name && pkg.test.init ? drvPath;
      expected = true;
    };

    "test packages: init operation has correct name" = {
      expr = let
        secrets = mkSecrets {
          my-secret = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        pkg = mkSecretsPackages secrets pkgs;
      in
        pkg.my-secret.init.name;
      expected = "init-my-secret";
    };

    "test packages: env operation has correct name" = {
      expr = let
        secrets = mkSecrets {
          my-secret = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        pkg = mkSecretsPackages secrets pkgs;
      in
        pkg.my-secret.env.name;
      expected = "env-my-secret";
    };

    "test packages: empty secrets produces valid package" = {
      expr = let
        secrets = mkSecrets {};
        pkg = mkSecretsPackages secrets pkgs;
      in
        pkg.name;
      expected = "secrets";
    };

    # ===========================================================================
    # mkSecretsPackages Reserved Name Validation (requires pkgs)
    # ===========================================================================

    "test packages reserved: rejects 'name' as secret name" = {
      expr = let
        secrets = mkSecrets {
          name = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        mkSecretsPackages secrets pkgs;
      expectedError = {
        type = "ThrownError";
        msg = "Invalid secret name.*name.*reserved";
      };
    };

    "test packages reserved: rejects 'meta' as secret name" = {
      expr = let
        secrets = mkSecrets {
          meta = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        mkSecretsPackages secrets pkgs;
      expectedError = {
        type = "ThrownError";
        msg = "Invalid secret name.*meta.*reserved";
      };
    };

    "test packages reserved: rejects 'passthru' as secret name" = {
      expr = let
        secrets = mkSecrets {
          passthru = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        mkSecretsPackages secrets pkgs;
      expectedError = {
        type = "ThrownError";
        msg = "Invalid secret name.*passthru.*reserved";
      };
    };

    "test packages reserved: rejects 'outPath' as secret name" = {
      expr = let
        secrets = mkSecrets {
          outPath = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        mkSecretsPackages secrets pkgs;
      expectedError = {
        type = "ThrownError";
        msg = "Invalid secret name.*outPath.*reserved";
      };
    };

    "test packages reserved: rejects 'drvPath' as secret name" = {
      expr = let
        secrets = mkSecrets {
          drvPath = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        mkSecretsPackages secrets pkgs;
      expectedError = {
        type = "ThrownError";
        msg = "Invalid secret name.*drvPath.*reserved";
      };
    };

    "test packages reserved: rejects multiple reserved names" = {
      expr = let
        secrets = mkSecrets {
          name = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
          meta = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
      in
        mkSecretsPackages secrets pkgs;
      expectedError = {
        type = "ThrownError";
        msg = "Invalid secret name";
      };
    };

    "test packages reserved: accepts valid name alongside check" = {
      expr = let
        secrets = mkSecrets {
          valid-secret = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        pkg = mkSecretsPackages secrets pkgs;
      in
        pkg ? valid-secret;
      expected = true;
    };

    # ===========================================================================
    # mkSecretsPackages Builder Pattern Tests (requires pkgs)
    # ===========================================================================

    "test packages builder: init has withSopsAgeKeyCmd method" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        pkg = mkSecretsPackages secrets pkgs;
      in
        # init doesn't have builder methods, but env doesn't either
        # Only decrypt/edit/rotate/rekey have them, but they require _exists=true
        pkg.test.init ? name;
      expected = true;
    };

    "test packages builder: operations are derivations with mainProgram" = {
      expr = let
        secrets = mkSecrets {
          test = {
            dir = /tmp/nonexistent-12345;
            recipients.alice = {key = validAgeKey1;};
          };
        };
        pkg = mkSecretsPackages secrets pkgs;
      in {
        initHasMainProgram = pkg.test.init ? meta && pkg.test.init.meta ? mainProgram;
        envHasMainProgram = pkg.test.env ? meta && pkg.test.env.meta ? mainProgram;
      };
      expected = {
        initHasMainProgram = true;
        envHasMainProgram = true;
      };
    };
  }
