#!/bin/bash
. sslib.sh


#根据用户文件生成ssserver配置文件
create_json () {
    echo '{
   "server": "'$SERVER_IP'",
   "port_password": {' > $JSON_FILE.tmp
    
    awk '
    BEGIN {
        i=1;
    }
    ! /^#|^\s*$/ {
        port=$1;
        pw=$2;
        ports[i++] = port;
        pass[port]=pw;
    }
    END {
        for(j=1;j<i;j++) {
            port=ports[j];
            printf("        \"%s\": \"%s\"", port, pass[port]);
            if(j<i-1) printf(",");
            printf("\n");
        }
    }
    ' $USER_FILE >> $JSON_FILE.tmp
    echo '   },
   "timeout": '$C_TIMEOUT',
   "method": "'$C_METHOD'"
}' >> $JSON_FILE.tmp
    mv $JSON_FILE.tmp $JSON_FILE

}
run_ssserver () {
    ssserver -qq -c $JSON_FILE 2>/dev/null >/dev/null &
    echo $! > $SSSERVER_PID 
}
check_ssserver () {
    ps $(cat $SSSERVER_PID) | grep ssserver 2>/dev/null
    return $?
}
start_ss () {
    if [ -e $SSSERVER_PID ]; then
        if check_ssserver; then
            echo 'ss服务已启动，同一文件下不能启动多次！'
            exit 1
        else
            rm $SSSERVER_PID
        fi
    fi
    create_json

    if [ -e $SSCOUNTER_PID ]; then
        ps $(cat $SSCOUNTER_PID) | grep sscounter 2>&1 >/dev/null
        if [ $? -eq 0 ] ; then 
            kill `cat $SSCOUNTER_PID`
        else
            rm $SSCOUNTER_PID
        fi
    fi
    ( $DIR/sscounter.sh ) & 
    echo $! > $SSCOUNTER_PID
    run_ssserver 
    echo '启动中...'
    sleep 1
    if check_ssserver; then 
        echo 'ss服务器已启动'
    else
        echo 'ss服务启动失败'
        kill `cat $SSCOUNTER_PID`
        rm $SSCOUNTER_PID
        exit 1
    fi

}

stop_ss () {
    kill `cat $SSSERVER_PID`
    kill `cat $SSCOUNTER_PID`
    rm $SSSERVER_PID $SSCOUNTER_PID
    del_ipt_chains 2> /dev/null
    echo 'ss服务器已关闭'
}

add_user () {
    PORT=$1
    PWORD=$2
    TLIMIT=$3
    TLIMIT=`echo "$TLIMIT" |
            sed -E 's/[kK][bB]?/ * 1024/' |
            sed -E 's/[mM][bB]?/ * 1024 * 1024/' |
            sed -E 's/[gG][bB]?/ * 1024 * 1024 * 1024/' |
            sed -E 's/[tT][bB]?/ * 1024 * 1024 * 1024 * 1024/' |
            bc |
            awk '{printf("%.0f", $1)}'`
    if [ ! -e $USER_FILE ]; then
        echo "\
# 以空格、制表符分隔
# 端口 密码 流量限制
# 2345 abcde 1000000" > $USER_FILE;
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
# 重新生成配置文件，并加载
    if [ -e $SSSERVER_PID ]; then
        create_json
        kill -s SIGQUIT `cat $SSSERVER_PID`
        add_rules $PORT
        run_ssserver
    fi
# 更新流量记录文件
    update_or_create_traffic_file_from_users
}

del_user () {
    PORT=$1
    if [ -e $USER_FILE ]; then
        sed -i '/^\s*'$PORT'\s/ d' $USER_FILE
    fi
# 重新生成配置文件，并加载
    if [ -e $SSSERVER_PID ]; then
        create_json
        kill -s SIGQUIT `cat $SSSERVER_PID`
        del_rules $PORT
        run_ssserver
    fi
# 更新流量记录文件
    update_or_create_traffic_file_from_users
}

case $1 in
    add )
        shift
        add_user $1 $2 $3 $4
        ;;
    del )
        shift
        del_user $1
        ;;
    list )
        list_rules
        ;;
    start )
        start_ss 
        ;;
    stop )
        stop_ss 
        ;;
esac

