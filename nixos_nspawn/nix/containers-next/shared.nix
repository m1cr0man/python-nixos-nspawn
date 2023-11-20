{ lib }:
let
  inherit (builtins) toString;
  inherit (lib) elem types mkOption optionalAttrs;
in
rec {
  mkNetworkingOpts = type:
    let
      mkIPOptions = v: assert elem v [ 4 6 ]; {
        addrPool = mkOption {
          type = types.listOf types.str;
          default =
            if v == 4
            then [ "0.0.0.0/${toString (if type == "zone" then 24 else 28)}" ]
            else [ "::/64" ];

          description = ''
            Address pool to assign to a network. If
            <literal>::/64</literal> or <literal>0.0.0.0/24</literal> is specified,
            <citerefentry><refentrytitle>systemd.network</refentrytitle><manvolnum>5</manvolnum>
            </citerefentry> will assign an ULA IPv6 or private IPv4 address from
            the address-pool of the given size to the interface.

            Please note that NATv6 is currently not supported since <literal>IPMasquerade</literal>
            doesn't support IPv6. If this is still needed, it's recommended to do it like this:

            <screen>
            <prompt># </prompt>ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
            </screen>
          '';
        };
        nat = mkOption {
          default = true;
          type = types.bool;
          description = ''
            Whether to set-up a basic NAT to enable internet access for the nspawn containers.
          '';
        };
      };
    in
    assert elem type [ "veth" "zone" ]; {
      v4 = mkIPOptions 4;
      v6 = mkIPOptions 6;
    } // optionalAttrs (type == "zone") {
      hostAddresses = mkOption {
        default = [ ];
        type = types.listOf types.str;
        description = ''
          Address of the container on the host-side, i.e. the
          subnet and address assigned to <literal>vz-&lt;name&gt;</literal>.
        '';
      };
    };
}
