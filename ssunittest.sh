. `dirname $0`/sslib.sh

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
    cjson )
        create_json
        ;;
    anr )
        add_new_rules
        ;;
    dpr )
        del_pre_rules
        ;;
    start )
        start_ss 
        ;;
    iic )
        init_ipt_chains
        ;;
    dic )
        del_ipt_chains 2> /dev/null
        ;;
    ctra )
        update_or_create_traffic_file_from_users
        ;;
    calcrem )
        calc_remaining
        ;;
    ctal )
        check_traffic_against_limits
        ;;
esac

