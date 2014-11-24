#!/bin/bash
USER_FILE=ssusers

add_rules () {
    PORT=$1;
    iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
    iptables -A OUTPUT -p tcp --sport $PORT -j ACCEPT
    iptables -A INPUT -p udp --dport $PORT -j ACCEPT
    iptables -A OUTPUT -p udp --sport $PORT -j ACCEPT
}

del_rules () {
    PORT=$1;
    iptables -D INPUT -p tcp --dport $PORT -j ACCEPT
    iptables -D OUTPUT -p tcp --sport $PORT -j ACCEPT
    iptables -D INPUT -p udp --dport $PORT -j ACCEPT
    iptables -D OUTPUT -p udp --sport $PORT -j ACCEPT
}

list_rules () {
    iptables -vnx -L
}

add_user () {
    PORT=$1
    PWORD=$2
    CMETHED=$3
    TLIMIT=$4
    if [ ! -e $USER_FILE ]; then
        echo "\
# 以空格、制表符分隔
# 端口 密码 加密方式 流量限制
# 2345 abcde  aes-256-cfb 10GiB" > $USER_FILE;
    fi
    cat $USER_FILE |
    awk '
    {
        if($1=='$PORT') exit 1
    }'
    if [ $? -eq 0 ]; then
        echo "\
$PORT $PWORD $CMETHED $TLIMIT" >> $USER_FILE;
    else
        echo "用户已存在!"
    fi
}

del_user () {
    PORT=$1
    if [ -e $USER_FILE ]; then
        sed -i '/^\s*'$PORT'\s/ d' $USER_FILE
    fi
}
case $1 in
    add )
        shift
        add_rules $1
        ;;
    del )
        shift
        del_rules $1
        ;;
    list )
        list_rules
        ;;
    au )
        shift
        add_user $1 $2 $3 $4
        ;;
    du )
        shift
        del_user $1
        ;;
esac

