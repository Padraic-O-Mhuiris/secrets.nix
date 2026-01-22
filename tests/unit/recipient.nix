# Recipient module tests
{ctx}: let
  inherit (ctx) mkSecrets testDir validAgeKey1 validAgeKey2 validAgeKey3;
in {
  testKeyIsPreserved = {
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

  testTypeDefaultsToAge = {
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

  testDecryptPkgDefaultsToNull = {
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

  testDecryptPkgCanBeAFunction = {
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
      pkg = secrets.test.recipients.alice.decryptPkg;
    in
      pkg != null && (builtins.isFunction pkg || (builtins.isAttrs pkg && pkg ? __functor));
    expected = true;
  };

  testMultipleRecipients = {
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

  testMissingKeyThrows = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = testDir;
          recipients.alice = {};
        };
      };
    in
      secrets.test.recipients.alice.key;
    expectedError = {
      type = "ThrownError";
      msg = "option.*recipients.alice.key.*was accessed but has no value defined";
    };
  };

  testMultipleRecipientsWithDifferentKeys = {
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

  testDecryptPkgStoredCorrectly = {
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
      stored != null && (builtins.isFunction stored || (builtins.isAttrs stored && stored ? __functor));
    expected = true;
  };

  testDecryptPkgNullByDefault = {
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
}
