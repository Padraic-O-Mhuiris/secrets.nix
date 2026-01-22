# Age key validation tests
{ctx}: let
  inherit (ctx) mkSecrets testDir validAgeKey1 validAgeKey2;
in {
  testAcceptsValidKeyAlice = {
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

  testAcceptsValidKeyBob = {
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

  testRejectsEmptyString = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = testDir;
          recipients.alice = {key = "";};
        };
      };
    in
      secrets.test.recipients.alice.key;
    expectedError = {
      type = "ThrownError";
      msg = "not of type.*string matching the pattern age1";
    };
  };

  testRejectsTooShortKey = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = testDir;
          recipients.alice = {key = "age1abc";};
        };
      };
    in
      secrets.test.recipients.alice.key;
    expectedError = {
      type = "ThrownError";
      msg = "not of type.*string matching the pattern age1";
    };
  };

  testRejectsUppercaseKey = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = testDir;
          recipients.alice = {key = "AGE1YCT6CDZ4F2HGUAAMC0JQXJX0M00V2PUQACX0339MUTAGV8XMPFFQCXQL4v";};
        };
      };
    in
      secrets.test.recipients.alice.key;
    expectedError = {
      type = "ThrownError";
      msg = "not of type.*string matching the pattern age1";
    };
  };

  testRejectsWrongPrefix = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = testDir;
          recipients.alice = {key = "age2yct6cdz4f2hguaamc0jqxjx0m00v2puqacx0339mutagv8xmpffqcxql4v";};
        };
      };
    in
      secrets.test.recipients.alice.key;
    expectedError = {
      type = "ThrownError";
      msg = "not of type.*string matching the pattern age1";
    };
  };

  testRejectsSSHKey = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = testDir;
          recipients.alice = {key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...";};
        };
      };
    in
      secrets.test.recipients.alice.key;
    expectedError = {
      type = "ThrownError";
      msg = "not of type.*string matching the pattern age1";
    };
  };
}
