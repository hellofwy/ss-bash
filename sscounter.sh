#!/bin/bash
. sslib.sh

update_or_create_traffic_file_from_users
init_ipt_chains 
add_new_rules
calc_remaining
> $PORTS_ALREADY_BAN
check_traffic_against_limits

ISFIRST=1;
while true; do
# 是否第一次运行，第一次则生成临时流量记录
    if [ $ISFIRST -eq 1 ]; then 
        get_traffic_from_iptables_first_time
        ISFIRST=0;
    else
#计算每个时间间隔内的流量使用量
        get_traffic_from_iptables_now
        calc_traffic_between_intervel
    fi
# 将流量记录添加到文件中 
    update_traffic_record
# 验证流量是否超过预设值
    calc_remaining
    check_traffic_against_limits
    sleep $INTERVEL 
done
