for iface in end0 wan lan1 lan2 lan3 lan2_10 lan2_20; do
    echo f > /sys/class/net/$iface/queues/rx-0/rps_cpus
    echo 32768 > /sys/class/net/$iface/queues/rx-0/rps_flow_cnt
done
echo 32768 > /proc/sys/net/core/rps_sock_flow_entries

for q in 0 1 2 3;   do echo 1 > /sys/class/net/end0/queues/tx-$q/xps_cpus; done
for q in 4 5 6 7;   do echo 2 > /sys/class/net/end0/queues/tx-$q/xps_cpus; done
for q in 8 9 10 11; do echo 4 > /sys/class/net/end0/queues/tx-$q/xps_cpus; done
for q in 12 13 14 15; do echo 8 > /sys/class/net/end0/queues/tx-$q/xps_cpus; done

for iface in wan lan1 lan2 lan3 lan2_10 lan2_20; do
    echo f > /sys/class/net/$iface/queues/tx-0/xps_cpus
done
