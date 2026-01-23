# mkSecretsPackages tests (requires pkgs)
{ctx}: let
  inherit (ctx) mkSecrets mkSecretsPackages pkgs validAgeKey1 validAgeKey2 validAgeKey3;

  nonexistentDir = /tmp/nonexistent-12345;
in {
  # Top-level package structure
  testTopLevelPackageHasCorrectName = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.name;
    expected = "secrets";
  };

  testTopLevelPackageHasSecretInPassthru = {
    expr = let
      secrets = mkSecrets {
        my-secret = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg ? my-secret;
    expected = true;
  };

  testMultipleSecretsInPassthru = {
    expr = let
      secrets = mkSecrets {
        secret1 = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
        secret2 = {
          dir = nonexistentDir;
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

  # Secret package structure
  testSecretPackageHasCorrectName = {
    expr = let
      secrets = mkSecrets {
        api-key = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.api-key.name;
    expected = "secret-api-key";
  };

  testSecretPackageHasEncryptOperation = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.test ? encrypt;
    expected = true;
  };

  testSecretPackageHasEditOperation = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.test ? edit;
    expected = true;
  };

  testSecretPackageHasEnvOperation = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.test ? env;
    expected = true;
  };

  testEncryptOperationIsDerivation = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.test.encrypt ? name && pkg.test.encrypt ? drvPath;
    expected = true;
  };

  testEncryptOperationHasCorrectName = {
    expr = let
      secrets = mkSecrets {
        my-secret = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.my-secret.encrypt.name;
    expected = "encrypt-my-secret";
  };

  testEditOperationHasCorrectName = {
    expr = let
      secrets = mkSecrets {
        my-secret = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.my-secret.edit.name;
    expected = "edit-my-secret";
  };

  testEnvOperationHasCorrectName = {
    expr = let
      secrets = mkSecrets {
        my-secret = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.my-secret.env.name;
    expected = "env-my-secret";
  };

  testEmptySecretsProducesValidPackage = {
    expr = let
      secrets = mkSecrets {};
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.name;
    expected = "secrets";
  };

  # Reserved name validation
  testReservedRejectsNameAsSecretName = {
    expr = let
      secrets = mkSecrets {
        name = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.name;
    expectedError = {
      type = "ThrownError";
      msg = "Invalid secret name.*name.*reserved";
    };
  };

  testReservedRejectsMetaAsSecretName = {
    expr = let
      secrets = mkSecrets {
        meta = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.name;
    expectedError = {
      type = "ThrownError";
      msg = "Invalid secret name.*meta.*reserved";
    };
  };

  testReservedRejectsPassthruAsSecretName = {
    expr = let
      secrets = mkSecrets {
        passthru = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.name;
    expectedError = {
      type = "ThrownError";
      msg = "Invalid secret name.*passthru.*reserved";
    };
  };

  testReservedRejectsOutPathAsSecretName = {
    expr = let
      secrets = mkSecrets {
        outPath = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.name;
    expectedError = {
      type = "ThrownError";
      msg = "Invalid secret name.*outPath.*reserved";
    };
  };

  testReservedRejectsDrvPathAsSecretName = {
    expr = let
      secrets = mkSecrets {
        drvPath = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.name;
    expectedError = {
      type = "ThrownError";
      msg = "Invalid secret name.*drvPath.*reserved";
    };
  };

  testReservedRejectsMultipleReservedNames = {
    expr = let
      secrets = mkSecrets {
        name = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
        meta = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.name;
    expectedError = {
      type = "ThrownError";
      msg = "Invalid secret name";
    };
  };

  testReservedAcceptsValidName = {
    expr = let
      secrets = mkSecrets {
        valid-secret = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg ? valid-secret;
    expected = true;
  };

  # Derivation tests
  testOperationsHaveMainProgram = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in {
      encryptHasMainProgram = pkg.test.encrypt ? meta && pkg.test.encrypt.meta ? mainProgram;
      editHasMainProgram = pkg.test.edit ? meta && pkg.test.edit.meta ? mainProgram;
      envHasMainProgram = pkg.test.env ? meta && pkg.test.env.meta ? mainProgram;
    };
    expected = {
      encryptHasMainProgram = true;
      editHasMainProgram = true;
      envHasMainProgram = true;
    };
  };

  # Drv construction tests
  testDrvEncryptProducesDerivationWithCorrectName = {
    expr = let
      secrets = mkSecrets {
        my-secret = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.my-secret.__operations.encrypt pkgs;
    in
      drv.name;
    expected = "encrypt-my-secret";
  };

  testDrvEditProducesDerivationWithCorrectName = {
    expr = let
      secrets = mkSecrets {
        my-secret = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.my-secret.__operations.edit pkgs;
    in
      drv.name;
    expected = "edit-my-secret";
  };

  testDrvEnvProducesDerivationWithCorrectName = {
    expr = let
      secrets = mkSecrets {
        my-secret = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.my-secret.__operations.env pkgs;
    in
      drv.name;
    expected = "env-my-secret";
  };

  testDrvEncryptIsShellApplication = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test.__operations.encrypt pkgs;
    in
      drv ? meta && drv.meta ? mainProgram;
    expected = true;
  };

  testDrvEncryptMainProgramMatchesName = {
    expr = let
      secrets = mkSecrets {
        api-key = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.api-key.__operations.encrypt pkgs;
    in
      drv.meta.mainProgram;
    expected = "encrypt-api-key";
  };

  testDrvEnvMainProgramMatchesName = {
    expr = let
      secrets = mkSecrets {
        api-key = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.api-key.__operations.env pkgs;
    in
      drv.meta.mainProgram;
    expected = "env-api-key";
  };

  testDrvMultipleSecretsProduceIndependentDerivations = {
    expr = let
      secrets = mkSecrets {
        secret1 = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
        secret2 = {
          dir = nonexistentDir;
          recipients.bob = {key = validAgeKey2;};
        };
      };
      drv1 = secrets.secret1.__operations.encrypt pkgs;
      drv2 = secrets.secret2.__operations.encrypt pkgs;
    in {
      name1 = drv1.name;
      name2 = drv2.name;
      different = drv1.name != drv2.name;
    };
    expected = {
      name1 = "encrypt-secret1";
      name2 = "encrypt-secret2";
      different = true;
    };
  };

  testDrvSameSecretCalledTwiceReturnsEquivalent = {
    expr = let
      secrets = mkSecrets {
        test = {
          dir = nonexistentDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv1 = secrets.test.__operations.encrypt pkgs;
      drv2 = secrets.test.__operations.encrypt pkgs;
    in
      drv1.name == drv2.name;
    expected = true;
  };

  testDrvFormatJsonSecretEncryptHasCorrectName = {
    expr = let
      secrets = mkSecrets {
        config = {
          dir = nonexistentDir;
          format = "json";
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.config.__operations.encrypt pkgs;
    in
      drv.name;
    expected = "encrypt-config";
  };

  testDrvFormatEnvSecretEncryptHasCorrectName = {
    expr = let
      secrets = mkSecrets {
        dotenv = {
          dir = nonexistentDir;
          format = "env";
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.dotenv.__operations.encrypt pkgs;
    in
      drv.name;
    expected = "encrypt-dotenv";
  };

  testDrvMultiRecipientSecretProducesSingleEncryptDrv = {
    expr = let
      secrets = mkSecrets {
        shared = {
          dir = nonexistentDir;
          recipients = {
            alice = {key = validAgeKey1;};
            bob = {key = validAgeKey2;};
            server1 = {key = validAgeKey3;};
          };
        };
      };
      drv = secrets.shared.__operations.encrypt pkgs;
    in
      drv.name;
    expected = "encrypt-shared";
  };
}
