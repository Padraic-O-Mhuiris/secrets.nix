# Unit tests for secrets.nix
#
# Run with: nix-unit --flake .#tests
# Or: nix flake check
#
{
  lib,
  corePath ? ../../core,
}: let
  inherit (import corePath {inherit lib;}) mkSecrets;

  # Valid age keys for testing (from flake.nix examples)
  validAgeKey1 = "age1yct6cdz4f2hguaamc0jqxjx0m00v2puqacx0339mutagv8xmpffqcxql4v";
  validAgeKey2 = "age1wdw6tuppmmcufrh6wzgy93jah9wzppaqn69wt5un8qzz8lk5ep5ss6ed3f";
  validAgeKey3 = "age1jmxpfw8y5e5njm5fq08n65ceu7vuydx5l8wxk7hyu9s3x5qs93ysxqrd8l";

  # Test fixtures
  testDir = /tmp/test-secrets;
in {
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
}
