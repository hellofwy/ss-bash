USER_FILE=ssusers
JSON_FILE=ssmlt.json
SERVER_IP=127.0.0.1
C_METHOD="aes-256-cfb"
C_TIMEOUT=60

TRA_FORMAT='%-5d\t%s\n'
TRAFFIC_LOG=traffic.log
INTERVEL=15
IPT_TRA_LOG=ipt_tra.log
IPT_TRA_LOG_tmp=ipt_tra_log.tmp
MIN_TRA_LOG=min_tra.log

SS_IN_RULES=ssinput
SS_OUT_RULES=ssoutput

del_ipt_chains () {
    iptables -F $SS_IN_RULES
    iptables -F $SS_OUT_RULES
    iptables -D INPUT -j $SS_IN_RULES
    iptables -D OUTPUT -j $SS_OUT_RULES
    iptables -X $SS_IN_RULES
    iptables -X $SS_OUT_RULES
}
init_ipt_chains () {
    del_ipt_chains 2> /dev/null
    iptables -N $SS_IN_RULES
    iptables -N $SS_OUT_RULES
    iptables -A INPUT -j $SS_IN_RULES
    iptables -A OUTPUT -j $SS_OUT_RULES
}

add_rules () {
    PORT=$1;
    iptables -A $SS_IN_RULES -p tcp --dport $PORT -j ACCEPT
    iptables -A $SS_OUT_RULES -p tcp --sport $PORT -j ACCEPT
    iptables -A $SS_IN_RULES -p udp --dport $PORT -j ACCEPT
    iptables -A $SS_OUT_RULES -p udp --sport $PORT -j ACCEPT
}

add_reject_rules () {
    PORT=$1;
    iptables -A $SS_IN_RULES -p tcp --dport $PORT -j REJECT
    iptables -A $SS_OUT_RULES -p tcp --sport $PORT -j REJECT
    iptables -A $SS_IN_RULES -p udp --dport $PORT -j REJECT
    iptables -A $SS_OUT_RULES -p udp --sport $PORT -j REJECT
}

del_rules () {
    PORT=$1;
    iptables -D $SS_IN_RULES -p tcp --dport $PORT -j ACCEPT
    iptables -D $SS_OUT_RULES -p tcp --sport $PORT -j ACCEPT
    iptables -D $SS_IN_RULES -p udp --dport $PORT -j ACCEPT
    iptables -D $SS_OUT_RULES -p udp --sport $PORT -j ACCEPT
}

list_rules () {
    iptables -vnx -L $SS_IN_RULES
    iptables -vnx -L $SS_OUT_RULES
}

#del_pre_rules () {
#    if [ -e $IPT_RULES_HISTORY ]; then
#        for port in `cat $IPT_RULES_HISTORY`
#        do
#            del_rules $port
#        done 
#    fi
#}

add_new_rules () {
    ports=`awk '
        {
            if($0 !~ /^#|^\s*$/) print $1
        }
    ' $USER_FILE`
#    > $IPT_RULES_HISTORY
    for port in $ports
    do
        add_rules $port
#        echo $port >> $IPT_RULES_HISTORY
    done
}

update_or_create_traffic_file_from_users () {
#根据用户文件生成或更新流量记录
    while [ -e $TRAFFIC_LOG.lock ]; do
        sleep 1
    done
    touch $TRAFFIC_LOG.lock

    if [ ! -f $TRAFFIC_LOG ]; then
        awk '{if($1 > 0) printf("%-5d\t0\n", $1)}' $USER_FILE > $TRAFFIC_LOG
    else
        awk '
        BEGIN {
            i=1;
        }
        {
            if(FILENAME=="'$USER_FILE'"){
                if($0 !~ /^#|^\s*$/){
                    port=$1;
                    user[i++]=port;
                }
            }
            if(FILENAME=="'$TRAFFIC_LOG'"){
                uport=$1;
                utra=$2;
                uta[uport]=utra;
            }
        }
        END {
            for(j=1;j<i;j++) {
                port=user[j];
                if(uta[port]>0) {
                    printf("'$TRA_FORMAT'", port, uta[port])
                } else {
                    printf("%-5d\t0\n", port)
                }
            }
        }' $USER_FILE $TRAFFIC_LOG > $TRAFFIC_LOG.tmp
        mv -f $TRAFFIC_LOG.tmp $TRAFFIC_LOG
    fi

    rm $TRAFFIC_LOG.lock
}
calc_remaining () {
    awk '
    function print_in_gb(bytes) {
        tb=bytes/(1024*1024*1024*1024*1.0);
        if(tb>=1||tb<=-1) {
            printf("(%.2fTB)", tb);
        } else {
            gb=bytes/(1024*1024*1024*1.0);
            if(gb>=1||gb<=-1) {
                printf("(%.2fGB)", gb);
            } else {
                mb=bytes/(1024*1024*1.0);
                if(mb>=1||mb<=-1) {
                    printf("(%.2fMB)", mb);
                } else {
                    kb=bytes/(1024*1.0);
                    printf("(%.2fKB)", kb);
                }
            }
        }
    }
    BEGIN {
        i=1;
    }
    {
        if(FILENAME=="'$USER_FILE'"){
            if($0 !~ /^#|^\s*$/){
                port=$1;
                user[i++]=port;
                limit=$3;
                limits[port]=limit
            }
        }
        if(FILENAME=="'$TRAFFIC_LOG'"){
            uport=$1;
            utra=$2;
            uta[uport]=utra;
        }
    }
    END {
        printf("# port limit(in_TB/GB/MB/KB) used(in_TB/GB/MB/KB) remaining(in_TB/GB/MB/KB)\n");
        for(j=1;j<i;j++) {
            port=user[j];
            printf("%-5d\t", port);
           
            limit=limits[port]
            printf("%s", limit);
            print_in_gb(limit);
            printf("\t");
            
            used=uta[port];
            printf("%s", used);
            print_in_gb(used);
            printf("\t");
            
            remaining=limits[port]-uta[port];
            printf("%s", remaining);
            print_in_gb(remaining);
            printf("\n");
        }
    }' $USER_FILE $TRAFFIC_LOG > $TRAFFIC_LOG.res
}

ports_already_ban=ports_already_ban.tmp
check_traffic_against_limits () {
#根据用户文件查看流量是否超限
    ports_2ban=`awk '
    BEGIN {
        i=1;
    }
    {
        if(FILENAME=="'$USER_FILE'"){
            if($0 !~ /^#|^\s*$/){
                port=$1;
                user[i++]=port;
                limit=$3;
                limits[port]=limit
            }
        }
        if(FILENAME=="'$TRAFFIC_LOG'"){
            uport=$1;
            utra=$2;
            uta[uport]=utra;
        }
    }
    END {
        for(j=1;j<i;j++) {
            port=user[j];
            remaining=limits[port]-uta[port];
            if(remaining<=0) print port;
        }
    }' $USER_FILE $TRAFFIC_LOG` 
    for p in $ports_2ban; do
        if grep -q $p $ports_already_ban; then
            continue;
        else 
            del_rules $p
            add_reject_rules $p
            echo $p >> $ports_already_ban
        fi
    done
}

