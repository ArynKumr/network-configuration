**Purpose:** Installation, Database initialization, and Configuration of the Kea DHCPv4 engine.

>Note: Refer in the case dhcp-intial-conf.sh doesn't work out.

---
#### 1. Installation
```bash
curl -1sLf 'https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh' | bash
apt update && apt install -y isc-kea isc-kea-mysql
```

#### 2. Database Backend (MariaDB/MySQL)
Initialize the lease and host database:
```sql
-- Run in mysql shell
CREATE DATABASE kea_dhcp;
CREATE USER 'dilraj'@'localhost' IDENTIFIED BY 'dilraj';
GRANT ALL PRIVILEGES ON kea_dhcp.* TO 'dilraj'@'localhost';
FLUSH PRIVILEGES;
```
Initialize the schema:
```bash
kea-admin db-init mysql -u dilraj -p dilraj -n kea_dhcp
```

#### 3. Kea Configuration 
Kea uses **strict JSON**. Ensure no trailing commas or non-standard comments exist in production.
For Dhcp over IPv4:
```json
/*etc/kea/kea-dhcp4.conf*/
{
    "Dhcp4": {
        "interfaces-config": {
            "interfaces": ["enp8s0", "enp9s0", "enp11s0", "vlan10", "vlan20"]
        },
        "control-socket": {
            "socket-type": "unix",
            "socket-name": "/var/run/kea/kea4-ctrl-socket"
        },
        "hooks-libraries": [
          {
            "library": "/usr/lib/aarch64-linux-gnu/kea/hooks/libdhcp_mysql.so"
          },
          {
            "library": "/usr/lib/aarch64-linux-gnu/kea/hooks/libdhcp_host_cmds.so"
          }
        ],
        "expired-leases-processing": {
            "reclaim-timer-wait-time": 10,
            "flush-reclaimed-timer-wait-time": 25,
            "hold-reclaimed-time": 3600,
            "max-reclaim-leases": 100,
            "max-reclaim-time": 250,
            "unwarned-reclaim-cycles": 5
        },
        "calculate-tee-times": true,
        "valid-lifetime": 86400,
        "lease-database": {
            "type": "mysql",
            "name": "kea_dhcp",
            "user": "dilraj",
            "password": "dilraj",
            "host": "localhost",
            "port": 3306
        },
        "hosts-database": {
            "type": "mysql",
            "name": "kea_dhcp",
            "user": "dilraj",
            "password": "dilraj",
            "host": "localhost",
            "port": 3306
        },
        "option-data": [
            { "name": "domain-name-servers", "data": "8.8.8.8" }
        ],
        "subnet4": [
            {
                "id": 1,
                "subnet": "10.9.0.0/24",
                "pools": [{ "pool": "10.9.0.2 - 10.9.0.244" }],
                "option-data": [{ "name": "routers", "data": "10.9.0.1" }]
            },
            {
                "id": 2,
                "subnet": "10.10.10.0/24",
                "relay": { "ip-addresses": ["10.10.10.1"] },
                "pools": [{ "pool": "10.10.10.100 - 10.10.10.200" }],
                "option-data": [{ "name": "routers", "data": "10.10.10.1" }],
                "interface": "enp13s0" //To align the subnet to clients connected to a specific interface
            }
        ]
    }
}
```
**Validation:** `kea-dhcp4 -t /etc/kea/kea-dhcp4.conf`
**Application:** `systemctl restart isc-kea-dhcp4-server.service`
Similary for DHCP over IPv6
```json
{
    "Dhcp6": {
        "interfaces-config": {
            "interfaces": ["enp8s0", "enp9s0", "enp11s0", "vlan10", "vlan20"]
        },
       "control-socket": {
            "socket-type": "unix",
            "socket-name": "/var/run/kea/kea4-ctrl-socket"
        },
        "hooks-libraries": [
          {
            "library": "/usr/lib/aarch64-linux-gnu/kea/hooks/libdhcp_mysql.so"
          },
          {
            "library": "/usr/lib/aarch64-linux-gnu/kea/hooks/libdhcp_host_cmds.so"
          }
        ],
        "expired-leases-processing": {
            "reclaim-timer-wait-time": 10,
            "flush-reclaimed-timer-wait-time": 25,
            "hold-reclaimed-time": 3600,
            "max-reclaim-leases": 100,
            "max-reclaim-time": 250,
            "unwarned-reclaim-cycles": 5
        },
        "calculate-tee-times": true,
        "lease-database": {
            "type": "mysql",
            "name": "kea_dhcp",
            "user": "dilraj",
            "password": "dilraj",//Opt for stronger password in production
            "host": "localhost",
            "port": 3306
        },
        // Add this section to enable the Host Database
        "hosts-database": {
            "type": "mysql",
            "name": "kea_dhcp",
            "user": "dilraj",
            "password": "dilraj",
            "host": "localhost",
            "port": 3306
        },
        "option-data": [
            { "name": "dns-servers", "data": "2001:4860:4860::8888" }
        ],
        "subnet6": [
            {
                "id": 1,
                "subnet": "2001:db8:9::/64",
                "pools": [{ "pool": "2001:db8:9::100 - 2001:db8:9::ffff" }]
            }
        ]
    }


        "loggers": [
            {
                "name": "kea-dhcp6",
                "output_options": [
                    {
                        "output": "/var/log/kea/kea-dhcp6.log",
                        "pattern": "%d %-5p [%c] %m\n",
                        "maxsize": 1048576,
                        "maxver": 8
                    }
                ],
                // Supported values: FATAL, ERROR, WARN, INFO, DEBUG
                "severity": "INFO",
                "debuglevel": 0
            }
        ]
    }

```
Refer: [isc-kea](https://gitlab.isc.org/isc-projects/kea) repo for more info
For More DHCP Option Related configurations (Like PXE,Voip,Classless Stateless Routing), Refer [here](all-options.conf)
