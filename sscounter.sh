#!/bin/bash
. sslib.sh

update_or_create_traffic_file_from_users
init_ipt_chains 
#删除之前的iptables rules
#del_pre_rules
#添加最新的iptables rules
add_new_rules
calc_remaining
check_traffic_against_limits
> $ports_already_ban

ISFIRST=1;
while true; do
# 是否第一次运行，第一次则生成临时流量记录
    if [ $ISFIRST -eq 1 ]; then 
        echo "$(iptables -nvx -L $SS_IN_RULES)" "$(iptables -nvx -L $SS_OUT_RULES)" |
        sed -nr '/ [sd]pt:[0-9]{1,5}$/ s/[sd]pt:([0-9]{1,5})/\1/p' |
        awk '
        {
           trans=$2;
           port=$NF;
           tr[port]+=trans;
        }
        END {
            for(port in tr) {
                printf("'$TRA_FORMAT'", port, tr[port]) 
            }
        }
        ' > $IPT_TRA_LOG
        ISFIRST=0;
    else
#计算每个时间间隔内的流量使用量
        echo "$(iptables -nvx -L $SS_IN_RULES)" "$(iptables -nvx -L $SS_OUT_RULES)" |
        sed -nr '/ [sd]pt:[0-9]{1,5}$/ s/[sd]pt:([0-9]{1,5})/\1/p' |
        awk '
        {
           trans=$2;
           port=$NF;
           tr[port]+=trans;
        }
        END {
            for(port in tr) {
                printf("'$TRA_FORMAT'", port, tr[port]) 
            }
        }
        ' > $IPT_TRA_LOG_tmp  
        awk '
        { 
            if(FILENAME=="'$IPT_TRA_LOG_tmp'") {
                port=$1;
                tras=$2;
                tr[port]=tras;
            }
            if(FILENAME=="'$IPT_TRA_LOG'") {
                port=$1;
                tras=$2;
                pretr[port]=tras;
            }
        }
        END {
            for(port in tr) {
                min_tras=tr[port]-pretr[port];
                printf("'$TRA_FORMAT'", port, min_tras);
            }
        }
        ' $IPT_TRA_LOG_tmp $IPT_TRA_LOG > $MIN_TRA_LOG
        mv $IPT_TRA_LOG_tmp $IPT_TRA_LOG
    fi
# 将流量记录添加到文件中 
    while [ -e $TRAFFIC_LOG.lock ]; do
        sleep 1
    done
    touch $TRAFFIC_LOG.lock
    awk '
    BEGIN {
        i=1;
    }
    {
        if(FILENAME=="'$MIN_TRA_LOG'"){
            trans=$2;
            port=$1;
            ta[port]+=trans;
        }
        if(FILENAME=="'$TRAFFIC_LOG'"){
            uport=$1;
            utra=$2;
            uta[uport]=utra;
            useq[i++]=uport;
        }
    }
    END {
        for (j=1;j<i;j++) {
            pt=useq[j];
            printf("'$TRA_FORMAT'", pt, uta[pt]+ta[pt]);
        }
    }' $MIN_TRA_LOG $TRAFFIC_LOG > $TRAFFIC_LOG.tmp
    mv $TRAFFIC_LOG.tmp $TRAFFIC_LOG
    rm $TRAFFIC_LOG.lock
# 验证流量是否超过预设值
    calc_remaining
    check_traffic_against_limits
    sleep $INTERVEL 
done
