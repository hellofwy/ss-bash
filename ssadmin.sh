#!/bin/bash

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
esac

