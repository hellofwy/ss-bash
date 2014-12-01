INTERVEL=300

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do 
      DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
      SOURCE="$(readlink "$SOURCE")"
      [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" 
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
TMPDIR=$DIR/tmp
if [ ! -e $TMPDIR ]; then
    mkdir $TMPDIR;
    chmod 777 $TMPDIR;
fi

USER_FILE=$DIR/ssusers
JSON_FILE=$DIR/ssmlt.json
TRAFFIC_FILE=$DIR/sstraffic

SSSERVER_PID=$TMPDIR/ssserver.pid
SSCOUNTER_PID=$TMPDIR/sscounter.pid

TRA_FORMAT='%-5d\t%s\n'
TRAFFIC_LOG=$DIR/traffic.log
IPT_TRA_LOG=$TMPDIR/ipt_tra.log
MIN_TRA_LOG=$TMPDIR/min_tra.log
PORTS_ALREADY_BAN=$TMPDIR/ports_already_ban.tmp

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

add_new_rules () {
    ports=`awk '
        {
            if($0 !~ /^#|^\s*$/) print $1
        }
    ' $USER_FILE`
    for port in $ports
    do
        add_rules $port
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
    while [ -e $TRAFFIC_FILE.lock ]; do
        sleep 1
    done
    touch $TRAFFIC_FILE.lock
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
    }' $USER_FILE $TRAFFIC_LOG > $TRAFFIC_FILE.tmp
    mv $TRAFFIC_FILE.tmp $TRAFFIC_FILE
    rm $TRAFFIC_FILE.lock
}

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
        if grep -q $p $PORTS_ALREADY_BAN; then
            continue;
        else 
            del_rules $p
            add_reject_rules $p
            echo $p >> $PORTS_ALREADY_BAN
        fi
    done
}
get_traffic_from_iptables () {
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
        '
}

get_traffic_from_iptables_first_time () {
    get_traffic_from_iptables > $IPT_TRA_LOG
}

get_traffic_from_iptables_now () {
    get_traffic_from_iptables > $IPT_TRA_LOG.tmp
}

calc_traffic_between_intervel () {
        awk '
        { 
            if(FILENAME=="'$IPT_TRA_LOG.tmp'") {
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
        ' $IPT_TRA_LOG.tmp $IPT_TRA_LOG > $MIN_TRA_LOG
        mv $IPT_TRA_LOG.tmp $IPT_TRA_LOG
}
update_traffic_record () {
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
}
