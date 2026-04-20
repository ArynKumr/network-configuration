# Allow Traffic to firewall from WAN

Truth-Table

| Case | Source IP | Source Port | Public Facing ISP IP | Public Facing ISP Port | Protocol | 
| --- | --- | --- | --- | --- | --- |
| Case 1 | Specific | Specific | Specific | Specific | Specific | 
| Case 2 | ALL | ALL | Specific | Specific | Specific | 
| Case 3 | ALL | Specific | Specific | Specific | Specific |
| Case 4 | Specific | ALL | Specific | Specific | Specific |


1. Case 1 — Fully Locked (IP + Port + Protocol)

    **Meaning:** A specific remote IP at a specific port using a specific protocol connecting to our firewall's specific ISP IP at a specific port connects through.

    **Example:**
    - Remote client at 203.45.67.89:5000 (TCP)
    - Connects to firewall's Airtel IP 49.12.34.56:8000
    - Connection allowed only for this exact combination

    # IPV4

    ```bash
    nft add rule inet filter input \
        ip saddr <source_remote_ip> \
        <protocol> sport <source_remote_port> \
        ip daddr <firewall_public_isp_ip> \
        <protocol> dport <firewall_public_isp_port> \
        accept
    ```

    # IPV6

    ```bash
    nft add rule inet filter input \
        ip6 saddr <source_remote_ip6> \
        <protocol> sport <source_remote_port> \
        ip6 daddr <firewall_public_isp_ip6> \
        <protocol> dport <firewall_public_isp_port> \
        accept
    ```


1. Case 2 — Public Service (Port Only)

    **Meaning:** Anyone from public IP connecting to a specific port of our firewall's specific ISP IP connects through.

    **Example:**
    - Any remote IP at any port
    - Connects to firewall's Airtel IP 49.12.34.56:80
    - Connection allowed from any source

    # IPV4

    ```bash
    nft add rule inet filter input \
        ip daddr <firewall_public_isp_ip> \
        <protocol> dport <firewall_public_isp_port> \
        accept
    ```

    # IPV6

    ```bash
    nft add rule inet filter input \
        ip6 daddr <firewall_public_isp_ip6> \
        <protocol> dport <firewall_public_isp_port> \
        accept
    ```



1. Case 3 — Port-Restricted Clients (Any IP)


    **What it does:** Adds an input rule that accepts packets from any source IP, but only if they originate from a specific source port and are destined for a specific firewall public IP and port.

    # IPV4

    ```bash
    nft add rule inet filter input \
        <protocol> sport <source_remote_port> \
        ip daddr <firewall_public_isp_ip> \
        <protocol> dport <firewall_public_isp_port> \
        accept
    ```

    # IPV6

    ```bash
    nft add rule inet filter input \
        <protocol> sport <source_remote_port> \
        ip6 daddr <firewall_public_isp_ip6> \
        <protocol> dport <firewall_public_isp_port> \
        accept
    ```



1. Case 4 — IP-Restricted Clients (Any Source Port)

    **What it does:** Adds an input rule that accepts packets from a specific source IP destined for a specific firewall public IP and port, but allows any source port.

    # IPV4

    ```bash
    nft add rule inet filter input \
        ip saddr <source_remote_ip> \
        ip daddr <firewall_public_isp_ip> \
        <protocol> dport <firewall_public_isp_port> \
        accept
    ```

    # IPV6

    ```bash
    nft add rule inet filter input \
        ip6 saddr <source_remote_ip6> \
        ip6 daddr <firewall_public_isp_ip6> \
        <protocol> dport <firewall_public_isp_port> \
        accept
    ```