# Format extension and validation tests
{ctx}: let
  inherit (ctx) mkSecrets testDir validAgeKey1;
in {
  testExtensionBinNoExtension = {
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

  testExtensionJsonDotJson = {
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

  testExtensionYamlDotYaml = {
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

  testExtensionEnvDotEnv = {
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

  testDefaultIsBin = {
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

  testInvalidFormatRejected = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = testDir;
          format = "xml";
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      secrets.test-secret.format;
    expectedError = {
      type = "ThrownError";
      msg = "option.*format.*is not of type.*one of";
    };
  };

  testAllValidFormatsAccepted = {
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

  testInvalidFormatTomlRejected = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = testDir;
          format = "toml";
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      secrets.test.format;
    expectedError = {
      type = "ThrownError";
      msg = "one of.*bin.*json.*yaml.*env";
    };
  };

  testInvalidFormatTxtRejected = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = testDir;
          format = "txt";
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      secrets.test.format;
    expectedError = {
      type = "ThrownError";
      msg = "one of.*bin.*json.*yaml.*env";
    };
  };
}
