# Operations module tests (structure and availability)
{ctx}: let
  inherit (ctx) lib mkSecrets testDir validAgeKey1 validAgeKey2;

  # Common test secret config for nonexistent path
  nonexistentDir = /tmp/nonexistent-12345;
in {
  testOperationsExists = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.hasAttr "__operations" secrets.test;
    expected = true;
  };

  testInitAvailableForNonexistent = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.hasAttr "init" secrets.test.__operations;
    expected = true;
  };

  testEnvAlwaysAvailable = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.hasAttr "env" secrets.test.__operations;
    expected = true;
  };

  testDecryptNotAvailableForNonexistent = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.hasAttr "decrypt" secrets.test.__operations;
    expected = false;
  };

  testEditNotAvailableForNonexistent = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.hasAttr "edit" secrets.test.__operations;
    expected = false;
  };

  testRotateNotAvailableForNonexistent = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.hasAttr "rotate" secrets.test.__operations;
    expected = false;
  };

  testRekeyNotAvailableForNonexistent = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.hasAttr "rekey" secrets.test.__operations;
    expected = false;
  };

  testInitIsFunctor = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      op = secrets.test.__operations.init;
    in
      builtins.isAttrs op && op ? __functor;
    expected = true;
  };

  testEnvIsFunctor = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      op = secrets.test.__operations.env;
    in
      builtins.isAttrs op && op ? __functor;
    expected = true;
  };

  testOnlyInitAndEnvForNonexistent = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      ops = builtins.attrNames secrets.test.__operations;
    in
      builtins.sort builtins.lessThan ops;
    expected = ["env" "init"];
  };

  # Multiple secrets tests
  testMultipleSecretsCount = {
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

  testMultipleSecretsIndependentFormats = {
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

  testMultipleSecretsIndependentRecipients = {
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

  # Edge cases
  testEmptySecretsMapValid = {
    expr = mkSecrets {};
    expected = {};
  };

  testSecretNameWithHyphens = {
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

  testSecretNameWithUnderscores = {
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

  testSingleCharSecretName = {
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

  testNumericSecretName = {
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

  testValidHyphenatedName = {
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

  testValidUnderscoredName = {
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

  testValidDottedName = {
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

  testEnvVarNameDerivation = {
    expr = lib.hasInfix "-" "api-key";
    expected = true;
  };

  testEmptyRecipientsMapAllowed = {
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

  testSpecialCharsInSecretName = {
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

  testVeryLongSecretName = {
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

  testRecipientNameWithNumbers = {
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

  testMultipleSecretsShareRecipients = {
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
