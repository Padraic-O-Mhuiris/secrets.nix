# Example usage of the secrets flake-module
#
# Structure: flake.secrets.<group>.<secret>
#
# Groups organize secrets by environment/purpose (e.g., default, prod, staging).
# Each secret has recipients (who can decrypt) and file settings (where it's stored).
#
{...}: let
  #############################################################################
  # RECIPIENT DEFINITIONS
  #
  # Recipients are defined as attrsets of { name = "age public key"; }
  # Users compose these freely using Nix's // operator and inherit.
  #############################################################################
  # Admins: humans/CI who manage secrets (typically included in all secrets)
  admins = {
    # AGE-SECRET-KEY-1X6NC9SE3V4Z55LQDZCYASDMD0DCQFU9K3EDA5QKC3F5CTNLSZHJSC0JHWK
    alice = "age1v9z267t653yn0pklhy9v23hy3y430snqpeatzp48958utqnhedzq6uvtkd";
    # AGE-SECRET-KEY-1Z5E3JCXWWFMPQS9DFH6U2TFA7KZ4Z8DPSZ3Y7SVQSYFXAZQDXXVSR2298J
    bob = "age19t7cnvcpqxv5walahqwz7udv3rrelqm7enztwgk5pg3famr3sq7shzx0ry";
  };

  # Targets: machines/services that need specific secrets at runtime
  targets = {
    # AGE-SECRET-KEY-1WW7NT3FU3RMC5TJMD45TA4TWTPT4NXN9ZJR8UHU337W5ZEMWTFFQMW3L5V
    server1 = "age1dpnznv446qgzah35vndw5ys763frgz8h6exfmecn8cvnu394ty5q0cts7s";
    # AGE-SECRET-KEY-1HS7UEF9R0LC6DHDVLWNSDLKAHHRC4ML80JE8EV8P5Y6SFL9PF0SSA2VXF8
    laptop = "age1f6ulfp8qstfgm8e3lxrprcwz5ml3c338t3h5pvfrp7dtmr4g6sfs5fx20n";
  };

  # Composed groups for convenience
  allRecipients = admins // targets;
  prodServers = {inherit (targets) server1;};
in {
  flake.secrets = {
    ###########################################################################
    # DEFAULT GROUP
    #
    # Secrets stored at: secrets/<name>.<type>
    # Use for shared/common secrets not tied to a specific environment.
    ###########################################################################
    default = {
      # Minimal definition - just recipients
      # Path: secrets/api-key.yaml (default type is yaml)
      api-key.recipients = admins // prodServers;

      # Explicit file settings (showing defaults)
      # Path: secrets/shared-config.yaml
      shared-config = {
        recipients = allRecipients;
        file = {
          dir = "secrets"; # default for "default" group
          type = "yaml"; # default
        };
      };

      # JSON format
      # Path: secrets/service-account.json
      service-account = {
        recipients = admins;
        file.type = "json";
      };
    };

    ###########################################################################
    # PRODUCTION GROUP
    #
    # Secrets stored at: secrets/prod/<name>.<type>
    # Production environment secrets with stricter access.
    ###########################################################################
    prod = {
      # All admins + all targets
      # Path: secrets/prod/db-password.yaml
      db-password.recipients = allRecipients;

      # Restricted to single admin (e.g., root credentials)
      # Path: secrets/prod/root-password.yaml
      root-password.recipients = {inherit (admins) alice;};

      # Custom directory override
      # Path: secrets/prod/databases/postgres.yaml
      postgres = {
        recipients = admins // prodServers;
        file.dir = "secrets/prod/databases";
      };
    };

    ###########################################################################
    # STAGING GROUP
    #
    # Secrets stored at: secrets/staging/<name>.<type>
    # Staging environment - more permissive access for testing.
    ###########################################################################
    staging = {
      # Path: secrets/staging/db-password.yaml
      db-password.recipients = allRecipients;

      # Path: secrets/staging/test-credentials.json
      test-credentials = {
        recipients = allRecipients;
        file.type = "json";
      };
    };

    ###########################################################################
    # DEVELOPMENT GROUP
    #
    # Secrets stored at: secrets/dev/<name>.<type>
    # Development environment - all team members have access.
    ###########################################################################
    dev = {
      # Path: secrets/dev/local-db.yaml
      local-db.recipients = admins;

      # Path: secrets/dev/mock-api-key.yaml
      mock-api-key.recipients = admins // {inherit (targets) laptop;};
    };
  };
}
