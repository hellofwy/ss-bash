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

update_or_create_traffic_file_from_users
init_ipt_chains 
add_new_rules
calc_remaining
> $PORTS_ALREADY_BAN
check_traffic_against_limits

ISFIRST=1;
while true; do
# Generate temporary traffic records if you run first time
    if [ $ISFIRST -eq 1 ]; then 
        get_traffic_from_iptables_first_time
        ISFIRST=0;
        sleep $INTERVEL 
        continue
    else
# Calculate the traffic usage during each time interval
        get_traffic_from_iptables_now
        calc_traffic_between_intervel
    fi
# Add traffic records to a file 
    update_traffic_record
# Verify whether the traffic exceeds the preset value
    calc_remaining
    check_traffic_against_limits
    sleep $INTERVEL 
done
