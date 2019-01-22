#!/bin/bash
# This file is part of the rsyslog project, released under ASL 2.0

#  Starting actual testbench
. ${srcdir:=.}/diag.sh init

port="$(get_free_port)"
omhttp_start_server $port --fail-every 100

error_file=$(pwd)/$RSYSLOG_DYNNAME.omhttp.error.log
rm -f $error_file

generate_conf
add_conf '
#$DebugLevel 2
module(load="../contrib/omhttp/.libs/omhttp")

main_queue(queue.dequeueBatchSize="2048")

template(name="tpl" type="string"
	 string="{\"msgnum\":\"%msg:F,58:2%\"}")

# Echo message as-is for retry
template(name="tpl_echo" type="string" string="%msg%")

ruleset(name="ruleset_omhttp_retry") {
    action(
        name="action_omhttp"
        type="omhttp"
        errorfile="'$error_file'"
        template="tpl_echo"

        server="localhost"
        serverport="'$port'"
        restpath="my/endpoint"
        batch="on"
        batch.maxsize="100"
        batch.format="kafkarest"

        retry="on"
        retry.ruleset="ruleset_omhttp_retry"

        # Auth
        usehttps="off"
    ) & stop
}

ruleset(name="ruleset_omhttp") {
    action(
        name="action_omhttp"
        type="omhttp"
        errorfile="'$error_file'"
        template="tpl"

        server="localhost"
        serverport="'$port'"
        restpath="my/endpoint"
        batch="on"
        batch.maxsize="100"
        batch.format="kafkarest"

        retry="on"
        retry.ruleset="ruleset_omhttp_retry"

        # Auth
        usehttps="off"
    ) & stop
}

if $msg contains "msgnum:" then
    call ruleset_omhttp
'
startup
injectmsg  0 50000
shutdown_when_empty
wait_shutdown
omhttp_get_data $port my/endpoint kafkarest
omhttp_stop_server
seq_check  0 49999
exit_test
