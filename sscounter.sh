#!/bin/bash
TRA_FORMAT='%-5d\t%s\n'
USER_FILE=ssusers
TRAFFIC_LOG=traffic.log

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
    mv $TRAFFIC_LOG.tmp $TRAFFIC_LOG
fi

ISFIRST=1;
IPT_TRA_LOG_tmp=ipt_tra.log.tmp
IPT_TRA_LOG=ipt_tra.log
MIN_TRA_LOG=min_tra.log
while true; do
    if [ $ISFIRST -eq 1 ]; then 
        iptables -nvx -L |
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
        iptables -nvx -L |
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
    sleep 5 
done
