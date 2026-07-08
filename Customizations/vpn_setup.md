# VPN Firewall Integration

This document defines firewall rules for:

- Remote-access (user) VPN
- Site-to-site VPN

It also explains how VPN traffic interacts with webfilter / NFQUEUE.


1. Remote-Access (User VPN)
    - Remote Access VPN
        1. Allow VPN Tunnel Establishment

            This allows clients on the internet to establish the encrypted tunnel.

            ```bash
            nft add rule inet filter input \
                ip daddr <firewall_public_isp_ip> \
                <protocol> dport <firewall_public_isp_port> \
                accept
            ```

            ```bash
            nft add rule inet filter input \
                ip6 daddr <firewall_public_isp_ip> \
                <protocol> dport <firewall_public_isp_port> \
                accept
            ```

            Examples

            | VPN Type | Protocol | Port |
            | --- | --- | --- |
            | WireGuard | udp | 51820 |
            | OpenVPN | udp/tcp | 1194 |
            | IPsec IKE | udp | 500 / 4500 |

        1. Allow Traffic FROM VPN Subnet to Firewall

            Once the tunnel is up, packets originate from the VPN subnet, not the internet.

            ```bash
            nft add rule inet filter input \
                ip daddr <vpn_subnet>/<prefix> \
                accept
            ```

            ```bash
            nft add rule inet filter input \
                ip6 daddr <vpn_prefix>/<prefix_length> \
                accept
            ```

            Purpose

            *   Allows VPN users to:
                *   reach firewall services
                *   authenticate
                *   access routed resources

            Without this rule, VPN users connect but can’t pass traffic.

        1. Allow Traffic FROM VPN Subnet to lan clients unrestricted

            Packets originate from the VPN subnet which acts like another lan network.

            ```bash
                nft add element inet filter vpn_subnet {<vpn_subnet>}
                nft add element inet nat vpn_subnet {<vpn_subnet>}
                nft add element inet webfilter vpn_subnet {<vpn_subnet>}
            ```
            ```bash
                nft add element inet filter vpnv6_subnet {<vpnv6_subnet>}
                nft add element inet nat vpnv6_subnet {<vpnv6_subnet>}
                nft add element inet webfilter vpnv6_subnet {<vpnv6_subnet>}
            ```

            Purpose

            *   Allows VPN users to:
                *   reach firewall clients
                *   not affect their download quota

            Without this rule, VPN users connect but consumes its download quota.

1. Part B — Site-to-Site VPN
    - Site-to-site VPNs require strict peer validation.
        1. Allow Tunnel Establishment from Known Peer

            ```bash
            nft add rule inet filter input \
                ip saddr <source_remote_ip> \
                <protocol> sport <source_remote_port> \
                ip daddr <firewall_public_isp_ip> \
                <protocol> dport <firewall_public_isp_port> \
                accept
            ```

            ```bash
            nft add rule inet filter input \
                ip6 saddr <source_remote_ip6> \
                <protocol> sport <source_remote_port> \
                ip6 daddr <firewall_public_isp_ip6> \
                <protocol> dport <firewall_public_isp_port> \
                accept
            ```

            Why This Is Required

            *   Prevents rogue tunnel attempts
            *   Locks the VPN to a known peer


        1. Allow Traffic FROM Remote VPN Subnet

            After tunnel setup, traffic appears as coming from the remote VPN subnet.

            ```bash
            nft add rule inet filter input \
                ip daddr <vpn_subnet>/<prefix> \
                accept
            ```

            ```bash
            nft add rule inet filter input \
                ip6 daddr <vpn_prefix>/<prefix_length> \
                accept
            ```

            Purpose

            *   Enables:
                *   routed inter-site traffic
                *   service access
                *   monitoring


        1. Webfilter Considerations for Site-to-Site VPN
        

            By default:

            *   Do NOT send site-to-site VPN traffic to webfilter
            *   These links are typically:
                *   trusted
                *   application-specific
                *   non-web traffic

            If filtering is required:

            *   Treat remote subnet like LAN


        1. Security Model Summary
            

            | VPN Type | Internet Rule | Subnet Rule | Webfilter |
            | --- | --- | --- | --- |
            | User VPN | Public IP + Port | VPN subnet | Optional |
            | Site-to-site | IP + Port locked | VPN subnet | Usually No |

