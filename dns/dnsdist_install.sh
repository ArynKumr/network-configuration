#!/bin/bash
#Note: mariadb install is left out since this script assume its already installed
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "Run as root"; exit 1; }
apt install dnsdist luarocks libmariadb-dev-compat lua5.1 -y
luarocks install luasql-mysql MYSQL_INCDIR=/usr/include/mariadb/



mysql -u root firewall -e "CREATE USER 'dnsdist'@'localhost' IDENTIFIED BY '5BYLGBe9XwSNOHXDUIpy9QWUa99FPqp52LE6MY4s2SQ';" 2>&1 > /dev/null | true
mysql -u root firewall -e "GRANT SELECT ON firewall.* TO 'dnsdist'@'localhost';"
mysql -u root firewall -e "FLUSH PRIVILEGES;"

cat <<EOF > /etc/dnsdist/dnsdist.conf
local luasql = require "luasql.mysql"
addACL("127.0.0.1/8")
addACL("::1")

setWebserverConfig({
  address = "0.0.0.0:8083",
  dashboard = true
})

--[[
in mariadb:
MariaDB [(none)]> CREATE USER 'dnsdist'@'localhost' IDENTIFIED BY '1';
MariaDB [(none)]> GRANT ALL PRIVILEGES ON firewall.* TO 'dnsdist'@'localhost';
MariaDB [(none)]> FLUSH PRIVILEGES;
]]
-- =========================
-- Global Settings
-- =========================
print("=======================================================")
setSecurityPollSuffix("")
setMaxUDPOutstanding(10240)
setServerPolicy(firstAvailable)


-- Default upstream Server
newServer("8.8.8.8")
newServer("8.8.4.4:53")


-- Local IPs to listen on

-- addLocal("10.9.1.1")
-- addLocal("192.168.1.9")

-- Upstream pools
-- newServer({ address="10.9.0.2:53", pool="mypool"})
-- newServer({ address="192.168.1.16:53", pool="mypool_other"})


-- Function which makes a LuaRule to match on the local IP address of the query and sends to the appropriate pool
function makeToPool(ip)
    return function(dq)
        local result = dq.localaddr:toString() == ip
        --print("Address", dq.localaddr:toString(), "Result:", result, "Qname:", dq.qname:toString())
        return result
    end
end


-- addAction(LuaRule(makeToPool("10.9.0.1")),PoolAction("mypool"))
-- addAction(LuaRule(makeToPool("192.168.1.9")),PoolAction("mypool_other"))

-- =========================
-- Database Connection
-- =========================


local db_host = "localhost"
local db_user = "dnsdist"
local db_pass = "5BYLGBe9XwSNOHXDUIpy9QWUa99FPqp52LE6MY4s2SQ"
local db_name = "firewall"

function LocalAddrRule(ip)
    return function(dq)
        return dq.localaddr:toString() == ip
    end
end

local env = luasql.mysql()
local conn, err = env:connect(db_name, db_user, db_pass, db_host)

if not conn then
    print("Database connection failed: " .. tostring(err))
    return
end

print("Database connection successful.")

-- =========================
-- Load LAN IPs and Per-IP Upstreams
-- =========================

print("Loading LAN IPs and upstreams...")
local ifaceCursor, err = conn:execute([[SELECT
        li.network_interface_id AS nid,
        li.ip,
        ds.dns_for_dhcp_clients AS dns1,
        ds.dns_for_dhcp_clients AS dns2
 FROM lan_ips li
 LEFT JOIN dhcp_servers ds
     ON ds.network_interface_id = li.network_interface_id
    AND li.cidr = ds.cidr
 WHERE li.ip_type='ipv4']])

if ifaceCursor then
    local ifaceCount = 0
    local row = ifaceCursor:fetch({}, "a")

    while row do
        local ip = row.ip
        print("LAN row:", "nid=", tostring(row.nid), "ip=", tostring(ip), "dns1=", tostring(row.dns1), "dns2=", tostring(row.dns2))
        if ip and ip ~= "" then
            ifaceCount = ifaceCount + 1
            -- Bind on port 53
            addLocal(ip .. ":53")

            -- Bind on port 5300 (webfilter port)
            addLocal(ip .. ":5300")

            print("Listening on:", ip, "and", ip .. ":5300")

            local dns1 = row.dns1
            local dns2 = row.dns2
            local hasDns1 = dns1 and dns1 ~= ""
            local hasDns2 = dns2 and dns2 ~= ""

            if hasDns1 or hasDns2 then
                local poolName = "pool_" .. ip:gsub("%.", "_")

                print("Creating pool:", poolName)
                if hasDns1 then
                    print("Adding server:", dns1 .. ":53", "to pool:", poolName)
                    newServer({
                        address = dns1 .. ":53",
                        pool = poolName
                    })
                end

                if hasDns2 then
                    print("Adding server:", dns2 .. ":53", "to pool:", poolName)
                    newServer({
                        address = dns2 .. ":53",
                        pool = poolName
                    })
                end

                -- Interface → pool routing (continue processing)
                addAction(LuaRule(makeToPool(ip)), PoolAction(poolName, false))

                print("Upstreams", tostring(dns1), tostring(dns2), "assigned to", ip)
            else
                print("No upstreams assigned to", ip, "- using default policy")

            end
        end

        row = ifaceCursor:fetch(row, "a")
    end

    ifaceCursor:close()
    print("LAN IPs processed:", ifaceCount)
else
    print("Interface query failed: " .. tostring(err))
end

-- =========================
-- Load DNS Spoof Domains
-- =========================

print("Loading DNS spoof domains...")
local cursor, err = conn:execute("SELECT domain, ip_address AS ip FROM local_dns_entries")

if cursor then
    local spoofCount = 0
    local row = cursor:fetch({}, "a")

    while row do
        if row.domain and row.ip then
            local domain = row.domain

            -- Ensure FQDN format
            if not domain:match("%.$") then
                domain = domain .. "."
            end

            addAction(
                QNameRule(domain),
                SpoofAction({row.ip}),
                { name = domain }
            )

            print("Spoof rule added:", domain, "→", row.ip)
            spoofCount = spoofCount + 1
        else
            print("Skipping spoof row:", "domain=", tostring(row.domain), "ip=", tostring(row.ip))
        end

        row = cursor:fetch(row, "a")
    end

    cursor:close()
    print("Spoof rules processed:", spoofCount)
else
    print("Domain query failed: " .. tostring(err))
end

conn:close()
env:close()

-- =========================
-- Port 5300 Webfilter Logic
-- =========================

local function blockAOn5300(dq)
    if dq.qtype ~= DNSQType.A then return false end
    return dq.localaddr:getPort() == 5300
end

local function blockAAAAOn5300(dq)
    if dq.qtype ~= DNSQType.AAAA then return false end
    return dq.localaddr:getPort() == 5300
end

function printLocalAddr(dq)
      --print("Queried Address:",dq.localaddr:toString())
    return false
end

--[[
addAction(
	LuaRule(printLocalAddr),
	NoneAction()
)
]]
addAction(
    DSTPortRule(5300),
    SpoofAction({"0.0.0.0"})
)

addAction(
    DSTPortRule(5300),
    SpoofAction({"::"})
)

-- =========================
-- Strip HTTPS (Disable ECH)
-- =========================

addResponseAction(
    AllRule(),
    ClearRecordTypesResponseAction(DNSQType.HTTPS)
)

-- =========================
-- Control Socket
-- =========================

controlSocket("127.0.0.1:5199")
setKey("5BYLGBe9XwSNOHXDUIpy9QWUa99FPqp52LE6MY4s2SQ=")
EOF
systemctl restart dnsdist
