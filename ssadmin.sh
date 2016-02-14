#!/bin/bash

# Copyright (c) 2014 hellofwy
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do 
      DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
      SOURCE="$(readlink "$SOURCE")"
      [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" 
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

. $DIR/sslib.sh

usage () {
    cat $DIR/sshelp
}
wrong_para_prompt() {
    echo "Parameter input error!"
    echo "Try 'ssadmin.sh -h' for more information."
}

# Generate ssserver configuration files based on user files
create_json () {
    echo '{' > $JSON_FILE.tmp
    sed -E 's/(.*)/    \1/' $DIR/ssmlt.template >> $JSON_FILE.tmp 
    awk '
    BEGIN {
        i=1;
        printf("    \"port_password\": {\n");
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
        printf("    }\n");
    }
    ' $USER_FILE >> $JSON_FILE.tmp
    echo '}' >> $JSON_FILE.tmp
    mv $JSON_FILE.tmp $JSON_FILE

}

run_ssserver () {
    $SSSERVER -qq -c $JSON_FILE 2>/dev/null >/dev/null &
    echo $! > $SSSERVER_PID 
}

check_ssserver () {
    if [ -e $SSSERVER_PID ]; then
        ps $(cat $SSSERVER_PID) 2>/dev/null | grep $SSSERVER_NAME 2>/dev/null
        return $?
    else
        return 1
    fi
}

check_sscounter () {
    if [ -e $SSCOUNTER_PID ]; then
        ps $(cat $SSCOUNTER_PID) 2>/dev/null | grep sscounter 2>/dev/null
        return $?
    else
        return 1
    fi
}

start_ss () {
    if [ ! -e $USER_FILE ]; then
        echo "No user! please add a user."
        return 1
    fi
    if [ -e $SSSERVER_PID ]; then
        if check_ssserver; then
            echo 'ssserver has started！'
            return 1
        else
            rm $SSSERVER_PID
        fi
    fi
    create_json

    if [ -e $SSCOUNTER_PID ]; then
        if check_sscounter ; then 
            kill `cat $SSCOUNTER_PID`
        else
            rm $SSCOUNTER_PID
        fi
    fi

    echo 'Starting sscounter.sh...'
    ( $DIR/sscounter.sh ) & 
    echo $! > $SSCOUNTER_PID
    if check_sscounter; then 
        echo 'sscounter.sh has started'
    else
        echo 'sscounter.sh failed to start'
        return 1
    fi

    echo 'Starting ssserver...'
    run_ssserver 
    sleep 1
    if check_ssserver; then 
        echo 'ssserver has started'
    else
        echo 'ssserver failed to start'
        return 1
    fi
}

stop_ss () {
    if check_ssserver; then 
        kill `cat $SSSERVER_PID`
        rm $SSSERVER_PID 
        del_ipt_chains 2> /dev/null
        echo 'ssserver stopped'
    else
        echo 'ssserver was not started'
    fi
    if check_sscounter; then 
        kill `cat $SSCOUNTER_PID`
        rm $SSCOUNTER_PID
        echo 'sscounter.sh stopped'
    else
        echo 'sscounter.sh was not started'
    fi
}

restart_ss () {
    stop_ss
    start_ss
}
    
soft_restart_ss () {
    if check_ssserver; then 
        kill -s SIGQUIT `cat $SSSERVER_PID`
        echo 'ssserver stopped'
        kill `cat $SSCOUNTER_PID`
        echo 'sscounter.sh stopped'
        rm $SSSERVER_PID $SSCOUNTER_PID
        del_ipt_chains 2> /dev/null
        start_ss
    else
        echo 'ssserver was not started'
    fi
}

status_ss () {
    if check_ssserver; then 
        echo 'ssserver is running'
    else
        echo 'ssserver was not started'
    fi
    if check_sscounter; then 
        echo 'sscounter.sh is running'
    else
        echo 'sscounter.sh was not started'
    fi
}

bytes2gb () {
    TLIMIT=$1
    echo "$TLIMIT" |
    sed -E 's/[kK][bB]?/ * 1024/' |
    sed -E 's/[mM][bB]?/ * 1024 * 1024/' |
    sed -E 's/[gG][bB]?/ * 1024 * 1024 * 1024/' |
    sed -E 's/[tT][bB]?/ * 1024 * 1024 * 1024 * 1024/' |
    bc |
    awk '{printf("%.0f", $1)}'
}
check_port_range () {
    PORT=$1
    if (( ($PORT > 0) && ($PORT <= 65535 ) )); then
        return 0
    else
        return 1
    fi
}
add_user () {
    if [ "$#" -ne 3 ]; then
        wrong_para_prompt;
        return 1
    fi
    PORT=$1
    if check_port_range $PORT; then
        :
    else
        wrong_para_prompt;
        return 1
    fi
    PWORD=$2
    TLIMIT=$3
    TLIMIT=`bytes2gb $TLIMIT`
    if [ ! -e $USER_FILE ]; then
        echo "\
# Split by \t or space
# port password limitation
# 2345 abcde 1000000" > $USER_FILE;
    fi
    cat $USER_FILE |
    awk '
    {
        if($1=='$PORT') exit 1
    }'
    if [ $? -eq 0 ]; then
        echo "\
$PORT $PWORD $TLIMIT" >> $USER_FILE;
    else
        echo "The user you were trying to create already exists."
        return 1
    fi
# Rebuild and load the config
    if [ -e $SSSERVER_PID ]; then
        create_json
        kill -s SIGQUIT `cat $SSSERVER_PID`
        add_rules $PORT
        run_ssserver
    fi
# Update traffic log file
    update_or_create_traffic_file_from_users
    calc_remaining
}

del_user () {
    if [ "$#" -ne 1 ]; then
        wrong_para_prompt;
        return 1
    fi
    PORT=$1
    if check_port_range $PORT; then
        :
    else
        wrong_para_prompt;
        return 1
    fi
    if [ -e $USER_FILE ]; then
        sed -i '/^\s*'$PORT'\s/ d' $USER_FILE
    fi
# Rebuild and load the config
    if [ -e $SSSERVER_PID ]; then
        create_json
        kill -s SIGQUIT `cat $SSSERVER_PID`
        del_rules $PORT 2>/dev/null
        del_reject_rules $PORT 2>/dev/null
        run_ssserver
    fi
# Update traffic log file
    update_or_create_traffic_file_from_users
    calc_remaining
}

change_user () {
    if [ "$#" -ne 3 ]; then
        wrong_para_prompt;
        return 1
    fi
    PORT=$1
    if check_port_range $PORT; then
        :
    else
        wrong_para_prompt;
        return 1
    fi
    PWORD=$2
    TLIMIT=$3
    TLIMIT=`bytes2gb $TLIMIT`
    if [ ! -e $USER_FILE ]; then
        echo "No user! Please add a user first" 
        return 1
    fi
    if grep -q "^\s*$PORT\s" $USER_FILE; then
        cat $USER_FILE |
        awk '
        {
            if($1=='$PORT') {
                printf("'$PORT' '$PWORD' '$TLIMIT'\n");
            } else {
                print $0
            }
        }' > $USER_FILE.tmp;
        mv $USER_FILE.tmp $USER_FILE
        # Rebuild and load the config
        if [ -e $SSSERVER_PID ]; then
            create_json
            kill -s SIGQUIT `cat $SSSERVER_PID`
            add_rules $PORT
            run_ssserver
        fi
        # Update traffic log file
        update_or_create_traffic_file_from_users
        calc_remaining
    else
        echo "This user does not exist!"
        return 1
    fi
}

change_passwd () {
    if [ "$#" -ne 2 ]; then
        wrong_para_prompt;
        return 1
    fi
    PORT=$1
    if check_port_range $PORT; then
        :
    else
        wrong_para_prompt;
        return 1
    fi
    PWORD=$2
    if [ ! -e $USER_FILE ]; then
        echo "No user! Please add a user first" 
        return 1
    fi
    if grep -q "^\s*$PORT\s" $USER_FILE; then
        cat $USER_FILE |
        awk '
        {
            if($1=='$PORT') {
                printf("'$PORT' '$PWORD' %s\n", $3);
            } else {
                print $0
            }
        }' > $USER_FILE.tmp;
        mv $USER_FILE.tmp $USER_FILE
        # Rebuild and load the config
        if [ -e $SSSERVER_PID ]; then
            create_json
            kill -s SIGQUIT `cat $SSSERVER_PID`
            add_rules $PORT
            run_ssserver
        fi
        # Update traffic log file
        update_or_create_traffic_file_from_users
        calc_remaining
    else
        echo "This user does not exist!"
        return 1
    fi
}

change_limit () {
    if [ "$#" -ne 2 ]; then
        wrong_para_prompt;
        return 1
    fi
    PORT=$1
    if check_port_range $PORT; then
        :
    else
        wrong_para_prompt;
        return 1
    fi
    TLIMIT=$2
    TLIMIT=`bytes2gb $TLIMIT`
    if [ ! -e $USER_FILE ]; then
        echo "No user! Please add a user first"
        return 1
    fi
    if grep -q "^\s*$PORT\s" $USER_FILE; then
        cat $USER_FILE |
        awk '
        {
            if($1=='$PORT') {
                printf("'$PORT' %s '$TLIMIT'\n", $2);
            } else {
                print $0
            }
        }' > $USER_FILE.tmp;
        mv $USER_FILE.tmp $USER_FILE
        # Update traffic log file
        update_or_create_traffic_file_from_users
        calc_remaining
    else
        echo "This user does not exist!"
        return 1
    fi
}

change_all_limit () {
    if [ "$#" -ne 1 ]; then
        wrong_para_prompt;
        return 1
    fi
    TLIMIT=$1
    TLIMIT=`bytes2gb $TLIMIT`
    if [ ! -e $USER_FILE ]; then
        echo "No user! Please add a user first"
        return 1
    fi
    cat $USER_FILE |
    awk '
    {
        if($0 !~ /^#/ && $0 !~ /^\s.*$/) {
            printf("%s %s '$TLIMIT'\n", $1, $2);
        } else {
            print $0
        }
    }' > $USER_FILE.tmp;
    mv $USER_FILE.tmp $USER_FILE
    # Update traffic log file
    update_or_create_traffic_file_from_users
    calc_remaining
}

show_user () {
    if [ $# -eq 0 ]; then
        cat $TRAFFIC_FILE;
    else
        if [ "$#" -ne 1 ]; then
            wrong_para_prompt;
            return 1
        fi
        PORT=$1
        if check_port_range $PORT; then
            :
        else
            wrong_para_prompt;
            return 1
        fi
        res=`grep "^\s*$PORT\s" $TRAFFIC_FILE`
        if [ -z "$res" ]; then
            echo "This user does not exist!"
        else 
            head -n1 $TRAFFIC_FILE
            echo  "$res"
        fi
    fi
}

show_passwd () {
    if [ $# -eq 0 ]; then
        cat $USER_FILE;
    else
        if [ "$#" -ne 1 ]; then
            wrong_para_prompt;
            return 1
        fi
        PORT=$1
        if check_port_range $PORT; then
            :
        else
            wrong_para_prompt;
            return 1
        fi
        res=`grep "^\s*$PORT\s" $USER_FILE`
        if [ -z "$res" ]; then
            echo "This user does not exist!"
        else 
            head -n2 $USER_FILE
            echo  "$res"
        fi
    fi
}
reset_limit () {
    if [ ! -e $USER_FILE ]; then
        echo "No user! Please add a user first"
        return 1
    fi
    if [ $# -eq 0 ]; then
        cat $USER_FILE |
        awk '
        {
            if($0 !~ /^#/ && $0 !~ /^\s.*$/) {
                printf("%s %s 0\n", $1, $2);
            } else {
                print $0
            }
        }' > $USER_FILE.tmp;
        mv $USER_FILE.tmp $USER_FILE
        # Update traffic log file
        update_or_create_traffic_file_from_users
        calc_remaining
    else
        if [ "$#" -ne 1 ]; then
            wrong_para_prompt;
            return 1
        fi
        PORT=$1
        if check_port_range $PORT; then
            :
        else
            wrong_para_prompt;
            return 1
        fi
        if grep -q "^\s*$PORT\s" $USER_FILE; then
            cat $USER_FILE |
            awk '
            {
                if($1=='$PORT') {
                    printf("'$PORT' %s 0\n", $2);
                } else {
                    print $0
                }
            }' > $USER_FILE.tmp;
            mv $USER_FILE.tmp $USER_FILE
            # Update traffic log file
            update_or_create_traffic_file_from_users
            calc_remaining
        else
            echo "This user does not exist!"
            return 1
        fi
    fi
}

reset_used () {
    if [ ! -e $USER_FILE ]; then
        echo "No user! Please add a user first"
        return 1
    fi
    while [ -e $TRAFFIC_LOG.lock ]; do
        sleep 1
    done
    touch $TRAFFIC_LOG.lock
    if [ $# -eq 0 ]; then
        cat $TRAFFIC_LOG |
        awk '
        {
            if($0 !~ /^#/ && $0 !~ /^\s.*$/) {
                printf("%-5d\t0\n", $1);
            } else {
                print $0
            }
        }' > $TRAFFIC_LOG.tmp;
        mv $TRAFFIC_LOG.tmp $TRAFFIC_LOG
    else
        if [ "$#" -ne 1 ]; then
            wrong_para_prompt;
            return 1
        fi
        PORT=$1
        if check_port_range $PORT; then
            :
        else
            wrong_para_prompt;
            return 1
        fi
        if grep -q "^\s*$PORT\s" $USER_FILE; then
            cat $TRAFFIC_LOG |
            awk '
            {
                if($1=='$PORT') {
                    printf("%-5d\t0\n", '$PORT');
                } else {
                    print $0
                }
            }' > $TRAFFIC_LOG.tmp;
            mv $TRAFFIC_LOG.tmp $TRAFFIC_LOG
        else
            echo "This user does not exist!"
            rm $TRAFFIC_LOG.lock
            return 1
        fi
    fi
    rm $TRAFFIC_LOG.lock
    # Update traffic log file
    calc_remaining
}

if [ "$#" -eq 0 ]; then
    usage
    exit 0
fi
case $1 in
    -h|h|help )
        usage
        exit 0;
        ;;
    -v|v|version )
        echo 'ss-bash Version 1.0-beta.3-en, 2016-2-5, Copyright (c) 2014 hellofwy'
        exit 0;
        ;;
esac
if [ "$EUID" -ne 0 ]; then
    echo "Permission denied! Must run as root!"
    exit 1;
fi
if type $SSSERVER 2>&1 >/dev/null; then
    :
else
    echo "Command ssserver not found, please set the path of ssserver in sslib.sh"
    exit 1;
fi
case $1 in
    add )
        shift
        add_user $1 $2 $3
        ;;
    del )
        shift
        del_user $1
        ;;
    show )
        shift
        show_user $1
        ;;
    showpw )
        shift
        show_passwd $1
        ;;
    change )
        shift
        change_user $1 $2 $3
        ;;
    cpw )
        shift
        change_passwd $1 $2
        ;;
    clim )
        shift
        change_limit $1 $2
        ;;
    rlim )
        shift
        if [ $# -eq 0 ]; then
            echo "Please specify the port number"
            exit 1
        else
            reset_limit $1
        fi
        ;;
    change_all_limit )
        shift
        change_all_limit $1
        ;;
    reset_all_limit )
        shift
        reset_limit
        ;;
    rused )
        shift
        if [ $# -eq 0 ]; then
            echo "Please specify the port number"
            exit 1
        else
            reset_used $1
        fi
        ;;
    reset_all_used )
        shift
        reset_used
        ;;
    start )
        start_ss 
        ;;
    stop )
        stop_ss 
        ;;
    restart )
        restart_ss 
        ;;
    status )
        status_ss
        ;;
    soft_restart )
        soft_restart_ss 
        ;;
    lrules )
        list_rules
        ;;
    * )
        usage
        ;;
esac

