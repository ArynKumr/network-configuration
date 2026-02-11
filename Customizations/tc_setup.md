# Traffic Control (QoS) Setup & User Class Enforcement (Linux `tc`)

Purpose:  
Configure hierarchical traffic shaping so:

- interface capacity is defined once,
- unclassified traffic is safely contained,
- each user gets a dedicated speed lane, and
- nftables packet marks are physically enforced by the kernel scheduler.

This is where bandwidth limits actually happen.


# Interface-Level QoS Setup

> Note please reffer [Tc's actual documentation](https://www.man7.org/linux/man-pages/man8/tc.8.html) for a detailed explaination

- _(Run at interface configuration time and again at boot for all relevant interfaces)_ These commands prepare each interface (LAN and WAN) to accept user classes.


    1. Clean Slate (Remove Existing QDiscs)

        ```
        tc qdisc del dev <iface_name> root 2>/dev/null || true
        ```

    1. Attach the Scheduler (HTB)

        ```
        tc qdisc add dev <iface_name> root handle 1: htb default <default_class_ID> r2q 400
        ```
        - `default <default_class_ID>` → where unmarked traffic goes
        - `r2q 400` → balances precision vs CPU load on high-speed links

    1. Define the Master Pipe (Interface Speed)

        Purpose:  
        Declare the physical speed of the interface.  
        All user speeds are carved from this class.

        ```
        tc class add dev <iface_name> parent 1: classid 1:1 \
            htb rate <iface_speed>Gbit/Mbit/Kbit \
            ceil <iface_speed>Gbit/Mbit/Kbit
        ```


    1. Default / Guest Lane (Failsafe)

        Purpose:  
        Ensure untagged or unknown traffic does not starve the system.

        ```
        tc class add dev <iface_name> parent 1:1 classid 1:<default_class_ID> \
            htb rate <speed>Gbit/Mbit/Kbit \
            ceil <speed>Gbit/Mbit/Kbit
        ```


    1. Fairness Within the Default Lane

        Purpose:
        Prevent one flow from monopolizing the default class.

        ```
        tc qdisc add dev <iface_name> parent 1:<default_class_ID> \
            handle <default_class_ID>: sfq perturb 10
        ```

        Effect:  
        Traffic is reshuffled every 10 seconds to maintain fairness.


User-Level QoS Setup
--------------------

_(Run when a user comes online and is assigned a class)_

> Directionality matters:
> 
> - WAN interface → controls upload speed
> - LAN interface → controls download speed
>     

- Apply these steps on both sides as required.


    1. Create the User Lane

        Purpose:
        Assign a dedicated speed limit to the user.

        ```
        tc class add dev <iface_name> parent 1:1 classid 1:<user_class_id> \
            htb rate <user_plan_speed>Gbit/Mbit/Kbit \
            ceil <user_plan_speed>Gbit/Mbit/Kbit
        ```
        - `rate` → guaranteed bandwidth
        - `ceil` → absolute maximum allowed


    1. Fairness Within the User Lane

        Purpose:  
        Ensure multiple connections from the same user share bandwidth fairly.

        ```
        tc qdisc add dev <iface_name> parent 1:<user_class_id> \
            handle <user_class_id>: sfq perturb 10
        ```


    1. Bind nftables Marks to the User Lane

        Purpose:  
        This is the bridge between nftables and traffic control.

        ```
        tc filter add dev <iface_name> protocol ip parent 1:0 prio 1 \
            handle 0x0000<tc_class_marks>/0x0000FFFF fw \
            flowid 1:<user_class_id>
        ```
        - `fw` → match firewall mark
        - `0x0000<tc_class_marks>` → class identifier portion of the mark
        - `/0x0000FFFF` → mask isolates TC bits
        - `flowid 1:<user_class_id>` → push packet into the user’s lane<br><br>

        > Note: Set the marks on the user during user creation, such that the tc mark is like: 0x0000\<mark here\>. Only then will the tc rules be applied. Refer [this](user_login.md)

        Example:
        ```
        nft add element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
        ```

Bandwidth-Pool-Level QoS Setup
--------------------

_(Run when a set of user comes online and is assigned the same class)_

> Directionality matters:
> 
> - WAN interface → controls upload speed
> - LAN interface → controls download speed
>     

- Apply these steps on both sides as required.


    1. Create the Bandwidth-Pool Lane

        Purpose:  
        Assign a dedicated speed limit to the Bandwidth-Pool.

        ```
        tc class add dev <iface_name> parent 1:1 classid 1:<Bandwidth-Pool_class_id> \
            htb rate <Bandwidth-Pool_plan_speed>Gbit/Mbit/Kbit \
            ceil <Bandwidth-Pool_plan_speed>Gbit/Mbit/Kbit
        ```
        - `rate` → guaranteed bandwidth
        - `ceil` → absolute maximum allowed


    1. Fairness Within the Bandwidth-Pool Lane

        Purpose:  
        Ensure multiple connections from the same Bandwidth-Pool share bandwidth fairly.

        ```
        tc qdisc add dev <iface_name> parent 1:<Bandwidth-Pool_class_id> \
            handle <Bandwidth-Pool_class_id>: sfq perturb 10
        ```


    1. Bind nftables Marks to the Bandwidth-Pool Lane

        Purpose:  
        This is the bridge between nftables and traffic control.

        ```
        tc filter add dev <iface_name> protocol ip parent 1:0 prio 1 \
            handle 0x0000<tc_class_marks>/0x0000FFFF fw \
            flowid 1:<Bandwidth-Pool_class_id>
        ```
        - `fw` → match firewall mark
        - `0x0000<tc_class_marks>` → class identifier portion of the mark
        - `/0x0000FFFF` → mask isolates TC bits
        - `flowid 1:<Bandwidth-Pool_class_id>` → push packet into the Bandwidth-Pool’s lane <br><br>

        > Note: Set the marks on the Bandwidth-Pool during Bandwidth-Pool creation, such that the tc mark is like: 0x0000\<mark here\>. Only then will the tc rules be applied. Refer [this](user_login.md)

        Example:
        ```
        nft add element inet mangle Bandwidth-Pool4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
        ```
