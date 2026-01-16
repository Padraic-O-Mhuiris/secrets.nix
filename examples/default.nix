# Example usage of the secrets flake-module
{...}: let
  # Define recipient groups - users compose these as needed
  admins = {
    # AGE-SECRET-KEY-1X6NC9SE3V4Z55LQDZCYASDMD0DCQFU9K3EDA5QKC3F5CTNLSZHJSC0JHWK
    alice = "age1v9z267t653yn0pklhy9v23hy3y430snqpeatzp48958utqnhedzq6uvtkd";
    # AGE-SECRET-KEY-1Z5E3JCXWWFMPQS9DFH6U2TFA7KZ4Z8DPSZ3Y7SVQSYFXAZQDXXVSR2298J
    bob = "age19t7cnvcpqxv5walahqwz7udv3rrelqm7enztwgk5pg3famr3sq7shzx0ry";
  };

  targets = {
    # AGE-SECRET-KEY-1WW7NT3FU3RMC5TJMD45TA4TWTPT4NXN9ZJR8UHU337W5ZEMWTFFQMW3L5V
    server1 = "age1dpnznv446qgzah35vndw5ys763frgz8h6exfmecn8cvnu394ty5q0cts7s";
    # AGE-SECRET-KEY-1HS7UEF9R0LC6DHDVLWNSDLKAHHRC4ML80JE8EV8P5Y6SFL9PF0SSA2VXF8
    laptop = "age1f6ulfp8qstfgm8e3lxrprcwz5ml3c338t3h5pvfrp7dtmr4g6sfs5fx20n";
  };
in {
  # Default group - secrets stored at secrets/<name>.yaml
  flake.secrets.default.api-key.recipients = admins // {inherit (targets) server1;};

  # Production group - secrets stored at secrets/prod/<name>.yaml
  flake.secrets.prod.db-password.recipients = admins // targets;
  flake.secrets.prod.root-password.recipients = {inherit (admins) alice;};

  # Staging group - secrets stored at secrets/staging/<name>.yaml
  flake.secrets.staging.db-password.recipients = admins // targets;
}
