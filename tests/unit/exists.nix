# Existing secret tests (requires pkgs + git-tracked fixtures)
# Uses tests/fixtures/secrets/test-secret which must be git-added
{ctx}: let
  inherit (ctx) mkSecrets mkSecretsPackages pkgs fixturesSecretsDir validAgeKey1;
in {
  # Basic existence tests
  testExistsIsTrueForGitTrackedFixture = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      secrets.test-secret._exists;
    expected = true;
  };

  testPathResolvesToFixturePath = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.pathExists secrets.test-secret._path;
    expected = true;
  };

  # Operations availability
  testDecryptOperationAvailableForExisting = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.hasAttr "decrypt" secrets.test-secret.__operations;
    expected = true;
  };

  testEditOperationAvailableForExisting = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.hasAttr "edit" secrets.test-secret.__operations;
    expected = true;
  };

  testRotateOperationAvailableForExisting = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.hasAttr "rotate" secrets.test-secret.__operations;
    expected = true;
  };

  testRekeyOperationAvailableForExisting = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.hasAttr "rekey" secrets.test-secret.__operations;
    expected = true;
  };

  testInitNotAvailableForExisting = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
    in
      builtins.hasAttr "init" secrets.test-secret.__operations;
    expected = false;
  };

  testAllOperationsForExisting = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      ops = builtins.attrNames secrets.test-secret.__operations;
    in
      builtins.sort builtins.lessThan ops;
    expected = ["decrypt" "edit" "env" "rekey" "rotate"];
  };

  # Derivation tests
  testDrvDecryptHasCorrectName = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.decrypt pkgs;
    in
      drv.name;
    expected = "decrypt-test-secret";
  };

  testDrvEditHasCorrectName = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.edit pkgs;
    in
      drv.name;
    expected = "edit-test-secret";
  };

  testDrvRotateHasCorrectName = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.rotate pkgs;
    in
      drv.name;
    expected = "rotate-test-secret";
  };

  testDrvRekeyHasCorrectName = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.rekey pkgs;
    in
      drv.name;
    expected = "rekey-test-secret";
  };

  # Builder pattern tests
  testBuilderDecryptHasWithSopsAgeKeyCmd = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.decrypt pkgs;
    in
      drv ? withSopsAgeKeyCmd;
    expected = true;
  };

  testBuilderDecryptHasWithSopsAgeKeyCmdPkg = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.decrypt pkgs;
    in
      drv ? withSopsAgeKeyCmdPkg;
    expected = true;
  };

  testBuilderDecryptHasBuildSopsAgeKeyCmdPkg = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.decrypt pkgs;
    in
      drv ? buildSopsAgeKeyCmdPkg;
    expected = true;
  };

  testBuilderWithSopsAgeKeyCmdReturnsDerivation = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.decrypt pkgs;
      configured = drv.withSopsAgeKeyCmd "echo test-key";
    in
      configured ? name && configured ? drvPath;
    expected = true;
  };

  testBuilderWithSopsAgeKeyCmdPreservesName = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.decrypt pkgs;
      configured = drv.withSopsAgeKeyCmd "echo test-key";
    in
      configured.name;
    expected = "decrypt-test-secret";
  };

  testBuilderChainedPreservesMethods = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.decrypt pkgs;
      configured = drv.withSopsAgeKeyCmd "echo test-key";
    in {
      hasWithCmd = configured ? withSopsAgeKeyCmd;
      hasWithPkg = configured ? withSopsAgeKeyCmdPkg;
      hasBuild = configured ? buildSopsAgeKeyCmdPkg;
    };
    expected = {
      hasWithCmd = true;
      hasWithPkg = true;
      hasBuild = true;
    };
  };

  testBuilderEditHasBuilderMethods = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.edit pkgs;
    in {
      hasWithCmd = drv ? withSopsAgeKeyCmd;
      hasWithPkg = drv ? withSopsAgeKeyCmdPkg;
      hasBuild = drv ? buildSopsAgeKeyCmdPkg;
    };
    expected = {
      hasWithCmd = true;
      hasWithPkg = true;
      hasBuild = true;
    };
  };

  testBuilderRotateHasBuilderMethods = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.rotate pkgs;
    in {
      hasWithCmd = drv ? withSopsAgeKeyCmd;
      hasWithPkg = drv ? withSopsAgeKeyCmdPkg;
      hasBuild = drv ? buildSopsAgeKeyCmdPkg;
    };
    expected = {
      hasWithCmd = true;
      hasWithPkg = true;
      hasBuild = true;
    };
  };

  testBuilderRekeyHasBuilderMethods = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.rekey pkgs;
    in {
      hasWithCmd = drv ? withSopsAgeKeyCmd;
      hasWithPkg = drv ? withSopsAgeKeyCmdPkg;
      hasBuild = drv ? buildSopsAgeKeyCmdPkg;
    };
    expected = {
      hasWithCmd = true;
      hasWithPkg = true;
      hasBuild = true;
    };
  };

  # Rotate operation tests
  testRotateDerivationIsShellApplication = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.rotate pkgs;
    in
      drv ? meta && drv.meta ? mainProgram;
    expected = true;
  };

  testRotateMainProgramMatchesName = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.rotate pkgs;
    in
      drv.meta.mainProgram;
    expected = "rotate-test-secret";
  };

  testRotateWithBuilderKeyCmd = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.rotate pkgs;
      configured = drv.withSopsAgeKeyCmd "echo test-key";
    in
      configured ? name && configured ? drvPath;
    expected = true;
  };

  testRotateWithBuilderKeyCmdPreservesName = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.rotate pkgs;
      configured = drv.withSopsAgeKeyCmd "echo test-key";
    in
      configured.name;
    expected = "rotate-test-secret";
  };

  testRotateChainedPreservesMethods = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      drv = secrets.test-secret.__operations.rotate pkgs;
      configured = drv.withSopsAgeKeyCmd "echo test-key";
    in {
      hasWithCmd = configured ? withSopsAgeKeyCmd;
      hasWithPkg = configured ? withSopsAgeKeyCmdPkg;
      hasBuild = configured ? buildSopsAgeKeyCmdPkg;
    };
    expected = {
      hasWithCmd = true;
      hasWithPkg = true;
      hasBuild = true;
    };
  };

  testRotateAvailableInPackagesPassthru = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.test-secret ? rotate;
    expected = true;
  };

  testRotateRecipientAvailableWithDecryptPkg = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {
            key = validAgeKey1;
            decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" "echo test";
          };
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.test-secret.rotate ? recipient && pkg.test-secret.rotate.recipient ? alice;
    expected = true;
  };

  testRotateRecipientAliceIsDerivation = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {
            key = validAgeKey1;
            decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" "echo test";
          };
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.test-secret.rotate.recipient.alice ? name && pkg.test-secret.rotate.recipient.alice ? drvPath;
    expected = true;
  };

  testRotateRecipientHasCorrectName = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {
            key = validAgeKey1;
            decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" "echo test";
          };
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.test-secret.rotate.recipient.alice.name;
    expected = "rotate-test-secret";
  };

  # mkSecretsPackages with existing secrets
  testPackagesDecryptAvailableInPassthru = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.test-secret ? decrypt;
    expected = true;
  };

  testPackagesAllOperationsInPassthru = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {key = validAgeKey1;};
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in {
      hasDecrypt = pkg.test-secret ? decrypt;
      hasEdit = pkg.test-secret ? edit;
      hasRotate = pkg.test-secret ? rotate;
      hasRekey = pkg.test-secret ? rekey;
      hasEnv = pkg.test-secret ? env;
      noInit = !(pkg.test-secret ? init);
    };
    expected = {
      hasDecrypt = true;
      hasEdit = true;
      hasRotate = true;
      hasRekey = true;
      hasEnv = true;
      noInit = true;
    };
  };

  testPackagesDecryptRecipientAvailableWithDecryptPkg = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {
            key = validAgeKey1;
            decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" "echo test";
          };
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.test-secret.decrypt ? recipient && pkg.test-secret.decrypt.recipient ? alice;
    expected = true;
  };

  testPackagesDecryptRecipientAliceIsDerivation = {
    expr = let
      secrets = mkSecrets {
        test-secret = {
          dir = fixturesSecretsDir;
          recipients.alice = {
            key = validAgeKey1;
            decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" "echo test";
          };
        };
      };
      pkg = mkSecretsPackages secrets pkgs;
    in
      pkg.test-secret.decrypt.recipient.alice ? name && pkg.test-secret.decrypt.recipient.alice ? drvPath;
    expected = true;
  };
}
