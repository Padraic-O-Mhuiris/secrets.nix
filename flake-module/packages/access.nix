# Secret access/decryption package builder
# Produces a derivation that decrypts a secret after validating recipient membership
{lib}: {
  pkgs,
  groupName,
  secretName,
  secretConfig,
}: let
  inherit (lib) attrNames concatMapStringsSep;

  # Build recipient public key lookup table
  recipientKeys = concatMapStringsSep "\n" (name:
    let r = secretConfig.recipients.${name};
    in ''  ["${r.key}"]="${name}"''
  ) (attrNames secretConfig.recipients);

  # List recipient names for error messages
  recipientList = concatMapStringsSep "\n" (name:
    ''echo "  - ${name}"''
  ) (attrNames secretConfig.recipients);

in pkgs.writeShellApplication {
  name = "secrets-${groupName}-${secretName}-decrypt";
  runtimeInputs = [ pkgs.sops pkgs.age ];
  text = ''
    if [[ -z "''${DECRYPT_CMD:-}" ]]; then
      echo "Error: DECRYPT_CMD not set" >&2
      echo "" >&2
      echo "Set DECRYPT_CMD to a command that prints your age private key to stdout." >&2
      echo "" >&2
      echo "Examples:" >&2
      echo "  export DECRYPT_CMD='pass show keys/age/mykey'" >&2
      echo "  export DECRYPT_CMD='cat ~/.age/key.txt'" >&2
      echo "  export DECRYPT_CMD='op read op://Private/age-key/password'" >&2
      exit 1
    fi

    # Recipient public keys
    declare -A recipients=(
    ${recipientKeys}
    )

    # Get key and validate membership
    eval "$DECRYPT_CMD" | {
      read -r private_key
      public_key=$(echo "$private_key" | age-keygen -y)

      if [[ -z "''${recipients[$public_key]:-}" ]]; then
        echo "Error: your key is not a recipient of this secret" >&2
        echo "" >&2
        echo "Valid recipients:" >&2
        ${recipientList}
        exit 1
      fi

      echo "Decrypting as: ''${recipients[$public_key]}" >&2
      echo "$private_key" | sops -d --age-key-file /dev/stdin "${secretConfig._relPath}"
    }
  '';
}
