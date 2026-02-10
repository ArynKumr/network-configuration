# User Authentication

These commands are meant to be executed dynamically by:

*   a captive portal,
*   an authentication daemon,
*   or an orchestration backend.

They **modify live sets/maps** — nothing here is persistent unless saved.
***
**REQUIREMENTS:**

* [IP Routes are to configured for nftables](route_rule_setup.md)
* [Interfaces are to configured for nftables](iface_setup.md)
* [TC classes qdiscs and filters are to configured for user setup](tc_setup.md)
* * *
>In the case of bandwidth pool the users under that pool are to to be assigned same class id.
* * *

# Login/Logout commands

1. Deleting blocked entries.
    > Note: When creating new users following commands must be ran, so previous entries are removed.
    ```
    nft delete element inet filter blocked_users_v4 { <client_ip> }
    nft delete element inet filter blocked_users_macs { <client_mac> }
    nft delete element inet filter blocked_users_v4_mac { <client_ip> . <mac_address> }
    ```


1. Internet Access (Forward Chain)

    **Purpose:**  
    Allow the user to pass traffic through the Firewall to the internet.

    ```
    # For IP based
    nft add element inet filter allowed_ip4 { <client_ip> }
    # For Mac based
    nft add element inet filter allowed_macs { <client_mac> }
    # For IP+Mac based
    nft add element inet filter allowed_ip4_mac { <client_ip> . <mac_address> }

    ```


1. Captive Portal Bypass (NAT)

    **Purpose:**  
    Stop redirecting this user to the login / splash page.

    ```
    # For allowed ip based users
    nft add element inet nat allowed_ip4 { <client_ip> }
    # For allowed mac based users
    nft add element inet nat allowed_macs { <client_mac> }
    # For allowed IP+Mac based
    nft add element inet nat allowed_ip4_mac { <client_ip> . <mac_address> }
    ```

    > Note: Must keep these entries for users we don't want to show captive portal.


1. QoS & ISP Routing Mark

    **Purpose:**  
    Tag all traffic from this IP with a composite mark:  
    `0x00[ISP][CLASS]`

    ```
    # For IP based users, and IP+Mac based users
    nft add element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }

    # For Mac based users
    nft add element inet mangle user_mac_marks { <client_mac> : 0x00<isp_mark><tc_class_marks> }

    ```


1. Enable Web Inspection (HTTP / HTTPS and DNS)

    **Purpose:**  
    Send this user’s web traffic to the NFQUEUE inspection engine.

    ```
    nft add element inet webfilter ALLOW_ACCESS { <client_ip> }
    ```
    > Note: Same as above, only IPs are added to webfilter


1. Deleting Users
    **Purpose:**  
    Deleting the user.
    ```
    # For IP based users
    nft delete element inet filter allowed_ip4 { <client_ip> }
    nft delete element inet nat allowed_ip4 { <client_ip> }
    nft delete element inet mangle user4_marks { <client_ip> }
    nft delete element inet webfilter ALLOW_ACCESS { <client_ip> }
    nft add element inet filter blocked_users_v4 { <client_ip> }

    # For mac based users
    nft delete element inet filter allowed_macs { <client_mac> }
    nft delete element inet nat allowed_macs { <client_mac> }
    nft delete element inet mangle user_mac_marks { <client_mac> : 0x00<isp_mark><tc_class_marks> }
    nft delete element inet webfilter ALLOW_ACCESS { <client_ip> }
    nft add element inet filter blocked_users_macs { <client_mac> }

    # For IP+Mac based users
    nft delete element inet filter allowed_ip4_mac { <client_ip> . <mac_address> }
    nft delete element inet nat allowed_ip4_mac { <client_ip> . <mac_address> }
    nft delete element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
    nft delete element inet webfilter ALLOW_ACCESS { <client_ip> }
    nft add element inet filter blocked_users_v4_mac { <client_ip> . <mac_address> }

    ```

    > Note: We may keep `nat` entries to bypass captive portal for certain devices. Or optionally all devices who are IP/mac/IP+Mac based users. That means, those entries will only be deleted for web based users.


    > We must also delete the entries from the policy sets for the users we are logging out. Also make sure to ensure that if we delete a policy, the users are added to another policy first.

    ```
    nft delete element inet mangle user4_marks {<policy_users_ip> : 0x00<isp_id><tc_class_id>}
    nft delete element inet filter <policy_users_set> { <policy_users_ip> }
    nft delete element inet nat <policy_users_set> { <policy_users_ip> }
    ```