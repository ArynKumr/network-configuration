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

            Purpose

            *   Allows VPN users to:
                *   reach firewall services
                *   authenticate
                *   access routed resources

            Without this rule, VPN users connect but can’t pass traffic.

        1. Allow Traffic FROM VPN Subnet to lan clients unrestricted

            Packets originate from the VPN subnet which acts like another lan network.

            ```bash
                nft add rule inet mangle prerouting ip daddr <vpn_subnet> iifname @lan_ifaces meta mark set 0x00000069
                nft add rule inet mangle forward ip saddr <vpn_subnet> oifname @lan_ifaces meta mark set 0x00000069
            ```

            Purpose

            *   Allows VPN users to:
                *   reach firewall clients
                *   not affect their download quota

            Without this rule, VPN users connect but consumes its download quota.
            

        1. Web Filtering Integration (Optional but Important)

            > NOTE:  
            > VPN subnets must be explicitly integrated with the webfilter table.

            If VPN user traffic must be inspected by NFQUEUE:

            ```bash
            nft add rule inet webfilter SYS_WEBFILTER \
                ip saddr @<vpn_subnet> \
                ip saddr = @ALLOW_ACCESS \
                tcp dport { 80, 443 } \
                queue flags bypass to 0
            ```

            What This Does

            *   Sends VPN users’ HTTP/HTTPS traffic to netfilter
            *   Applies the same content filtering rules as LAN users
            *   `bypass` ensures internet still works if the filter crashes


            If Only Specific VPN Users Should Be Filtered

            Add individual VPN user IPs to `ALLOW_ACCESS` instead of the whole subnet.

            ```bash
            nft add element inet webfilter ALLOW_ACCESS { <vpn_user_ip> }
            ```


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

