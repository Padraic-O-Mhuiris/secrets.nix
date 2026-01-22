# Derived properties tests
{ctx}: let
  inherit (ctx) lib mkSecrets testDir validAgeKey1;
in {
  testPathCombinesDirAndFileName = {
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

  testPathWithJsonFormat = {
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

  testDirIsPreserved = {
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

  testProjectOutPathStartsWithDotSlash = {
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

  testExistsIsFalseForNonexistentPath = {
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

  testFileNameCorrectForAllFormats = {
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

  testPathCombinesDirAndFileNameCorrectly = {
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

  testDirAcceptsAbsolutePath = {
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

  testDirPathPreservedInConfig = {
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

  testMissingDirThrows = {
    expr = let
      secrets = mkSecrets {
        test = {
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      secrets.test.dir;
    expectedError = {
      type = "ThrownError";
      msg = "option.*dir.*was accessed but has no value defined";
    };
  };
}
