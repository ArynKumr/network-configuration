# Chain Flush — Policy Reorder / Cleanup Module

## Purpose

`nft flush chain` removes **all rules inside a chain**

# Core Commands

## 1. Flush Main Forward Chain

```bash
nft flush chain filter FILTER_FORWARD
```

## 2. Flush NAT Prerouting Chain

```bash
nft flush chain nat NAT_PRE
```

## 3. Flush NAT Postrouting Chain

```bash
nft flush chain nat NAT_POST
```

## 4. Flush Filter Policy Chain

```bash
nft flush chain inet filter <POLICY_NAME>
```

## 5. Flush NAT Policy Chains

```bash
nft flush chain inet nat PRE_NAT_<POLICY_NAME>
nft flush chain inet nat POST_NAT_<POLICY_NAME>
```
---
>NOTE: Remember to add the return traffic rule to the chainafter the chain is flushed and before the new rules are applied
---
## Purpose

`nft add rule inet <table_name> <chain_name> return` allows the traffic which enters the chain and dosent match any rules in the chain to **return to the parent chain**

# Core Commands

## 1. Add return rules to Main Forward Chain

```bash
nft add rule filter FILTER_FORWARD return
```
## 2. Add return rules to NAT Prerouting Chain

```bash
nft add rule nat NAT_PRE return
```
## 3. Add return rules to NAT Postrouting Chain

```bash
nft add rule nat NAT_POST return
```
## 4. Add return rules to Filter Policy Chain

```bash
nft add rule inet filter <POLICY_NAME> return
```
## 5. Add return rules to NAT Policy Chains

```bash
nft add rule inet nat PRE_NAT_<POLICY_NAME> return
nft add rule inet nat POST_NAT_<POLICY_NAME> return
```