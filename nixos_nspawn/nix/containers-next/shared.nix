{ lib }:
let
  inherit (builtins) toString;
  inherit (lib)
    elem
    types
    mkOption
    optionalAttrs
    mkDefault
    ;
in
rec {
  # Options ignored when creating data.json files.
  # Also controls what options only trigger a container reload.
  ignoredOptions = [
    "config"
    "nixpkgs"
    "toplevel"
    "timeoutStartSec"
  ];
  jsonContent =
    containerConfig: builtins.toJSON (builtins.removeAttrs containerConfig ignoredOptions);

  yesNo = v: if v then "yes" else "no";

  ifacePrefix = type: if type == "veth" then "ve" else "vz";

  # Both veth and zone interfaces use the same basic settings.
  # Copied from ${pkgs.systemd}/lib/systemd/network/80-container-{ve,vz}.network
  mkNetwork =
    name: type: extraConfig:
    let
      prefix = ifacePrefix type;
      v4PrefixLen = if type == "veth" then "28" else "24";
    in
    {
      "20-${prefix}-${name}" = lib.mkMerge [
        extraConfig
        {
          matchConfig = {
            Name = "${prefix}-${name}";
            Driver = if type == "veth" then "veth" else "bridge";
          };
          address = [ "0.0.0.0/${v4PrefixLen}" ];
          linkConfig.RequiredForOnline = mkDefault "no";
          networkConfig = {
            DHCPServer = mkDefault "yes";
            IPMasquerade = mkDefault "both";
            LLDP = mkDefault "yes";
            EmitLLDP = mkDefault "customer-bridge";
            IPv6AcceptRA = mkDefault "no";
            IPv6SendRA = mkDefault "yes";
            # This strays from the defaults - the standard config sets up both a private
            # ipv4 subnet and a link local address.
            # In practice, it only needs the LLIPv6 address.
            LinkLocalAddressing = mkDefault "ipv6";
          };
          dhcpServerConfig = {
            PersistLeases = mkDefault "runtime";
            # This option is extremely new - not enabled for now.
            # LocalLeaseDomain = mkDefault "_dhcp";
          };
        }
      ];
    };

  # Similarly copied from ${pkgs.systemd}/lib/systemd/network/80-container-host0.network
  mkContainerNetwork = extraConfig: {
    "20-host0" = lib.mkMerge [
      extraConfig
      {
        matchConfig = {
          Kind = "veth";
          Name = "host0";
          Virtualization = "container";
        };
        networkConfig = {
          DHCP = mkDefault "yes";
          LLDP = mkDefault "yes";
          EmitLLDP = mkDefault "customer-bridge";
          # Since we disabled LLIPv4 host-side, disable it container-side also.
          LinkLocalAddressing = mkDefault "ipv6";
        };
        dhcpConfig.UseTimezone = "yes";
      }
    ];
  };
}
