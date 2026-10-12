# Secret and recipient names end up in file names, command names and shell
# variable names; these helpers keep that mapping in one place.
{lib}: {
  namePattern = "[A-Za-z][A-Za-z0-9._-]*";

  # api-key -> API_KEY, my.key -> MY_KEY
  toEnvVar = s: lib.toUpper (builtins.replaceStrings ["-" "."] ["_" "_"] s);
}
