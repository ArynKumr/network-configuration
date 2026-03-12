Case 1

nft add element inet filter allowed_ip4 { <destination_ip> }
nft add element inet mangle c1_src_client_mark {<destination_ip> . <protocol> . <destination_port> : 0x00<isp_id><tc_class_id>}
nft add element inet mangle c1_dst_client_mark {<destination_ip> . <protocol> . <destination_port> : 0x00<isp_id><tc_class_id>}

nft add map inet mangle src_client_mark '{type ipv4_addr . inet_proto . inet_service : mark ;}'
nft add map inet mangle dst_client_mark '{type ipv4_addr . inet_proto . inet_service : mark ;}'
nft insert rule inet mangle prerouting meta mark set ip saddr . meta l4proto . th sport map @src_client_mark
nft insert rule inet mangle postrouting meta mark set ip daddr . meta l4proto . th dport map @dst_client_mark

nft add set inet nat <dmz_set_name> '{type ipv4_addr . ipv4_addr}'
nft insert rule inet nat NAT_PRE ip daddr . ip saddr @<dmz_set_name> dnat to <destination_ip>:<destination_port>

On Login

nft add element inet nat <dmz_set_name> {<public_facing_isp_ip> . <public_remote_ip>}

Case 2

nft add element inet filter allowed_ip4 { <destination_ip> }
nft add element inet mangle user4_marks { <destination_ip> : 0x00<isp_id><tc_class_id> }
nft add set inet nat <dmz_set_name> '{type ipv4_addr . ipv4_addr}'
nft insert rule inet nat NAT_PRE ip daddr . ip saddr @<dmz_set_name> dnat to <destination_ip>

On Login

nft add element inet nat <dmz_set_name> {<public_facing_isp_ip> . <public_remote_ip>    }