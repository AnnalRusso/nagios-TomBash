#!/bin/bash
#set -x
###########################################
#Annalisa Russo for     #
########################
help(){
        echo "usage: $0 <-w warning threshold> <-c error_threshold>"
}

#Standard return codes for Nagios
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

while getopts w:c: flag
    do
        case $flag in
            w)
                WARN_THRESHOLD=$OPTARG
                ;;
            c)
                ERROR_THRESHOLD=$OPTARG
                ;;
            *)
                help
                exit 1
                ;;
        esac
done

#echo "WARN_THRESHOLD=$WARN_THRESHOLD"
#echo "ERROR_THRESHOLD=$ERROR_THRESHOLD"

#get tomcat running PID
PID=`ps aux|grep java|grep tomcat|grep "Djava.rmi.server.hostname=127.0.0.1" | awk '{print $2}'`
if [ -z "$PID" ]; then
        echo "NOK - Tomcat not running or -Djava.rmi.server.hostname=127.0.0.1 JVM Argument not set!"
        exit 1
else
        #check if PID is an integer number
        TESTPID=`echo $PID | sed 's/[0-9]//g'`
        if [ -n "$TESTPID" ]; then
                echo "NOK - PID [$PID] is not a valid integer number!"
                exit 1
        fi
fi
#echo "OK - Tomcat Running with PID=[$PID]"

#get listening RMI port number
RMIPORT=`ps -ef | grep $PID | awk '{ for (i=1;i<=NF;i++) {if ($i~/-Dcom.sun.management.jmxremote.rmi.port=/) {split($i,arr,"="); print arr[2]}} }'`
if [ -z "$RMIPORT" ]; then
        echo "NOK - Could not get the RMI port number!"
        exit 1
else
        #check if RMI port is an integer number
        TESTRMIPORT=`echo $RMIPORT | sed 's/[0-9]//g'`
        if [ -n "$TESTRMIPORT" ] ; then
                echo "NOK - RMI port [$RMIPORT] is not a valid integer number!"
                exit 1
        fi

fi
#echo "OK - RMIPORT=[$RMIPORT]"

# Create JMX query URL
JARPATH='/root/tomcat_debugtools/jmx-query.jar'
AJPBIO=`echo ${RMIPORT%??}09`

#echo 'requests'
#echo 'Time(ms) send(byte) received(byte) URI QueryStr'

java -jar ${JARPATH} 'service:jmx:rmi:///jndi/rmi://localhost:'${RMIPORT}'/jmxrmi' 'Catalina:type=RequestProcessor,worker="ajp-bio-'$AJPBIO'",name=*' workerThreadName requestProcessingTime requestBytesReceived requestBytesSent currentUri  currentQueryString | grep -v unavailable | grep -v requestProcessingTime | awk '{print $3, $4, $5, $6, $7}' | sort -nr > /tmp/output.$$

REQ_WARN_LIST=""
REQ_ERROR_LIST=""
EXIT_MSG='OK'
EC=$OK
while read line; do
        #echo $line
        requestProcessingTime=`echo $line | awk '{print $1}'`
        requestBytesReceived=`echo $line | awk '{print $2}'`
        requestBytesSent=`echo $line | awk '{print $3}'`
        currentUri=`echo $line | awk '{print $4}'`
        currentQueryString=`echo $line | awk '{print $5}'`

        #echo "$requestProcessingTime $requestBytesReceived $requestBytesSent $currentUri $currentQueryString"

        #compare with input thresholds for warning and error and generate dynamically the lists
        if [ "$requestProcessingTime" -ge "$ERROR_THRESHOLD" ]; then
                REQ_ERROR_LIST=`echo "$REQ_ERROR_LIST --- Time(ms): $requestProcessingTime, SentB: $requestBytesSent, RecvB: $requestBytesReceived, URI: $currentUri, QueryStr: $currentQueryString"`
                EXIT_MSG=`echo $EXIT_MSG CRITICAL`
        elif [ "$requestProcessingTime" -ge "$WARN_THRESHOLD" ]; then
                REQ_WARN_LIST=`echo "$REQ_WARN_LIST --- Time(ms): $requestProcessingTime, SentB: $requestBytesSent, RecvB: $requestBytesReceived, URI: $currentUri, QueryStr: $currentQueryString"`
                EXIT_MSG=`echo $EXIT_MSG WARNING`
        fi
done < /tmp/output.$$

#final determination of exit message type and code
if [ `echo $EXIT_MSG | grep CRITICAL | wc -l` -gt 0 ]; then
        EXIT_MSG='CRITICAL'
        EC=$CRITICAL
elif [ `echo $EXIT_MSG | grep WARNING | wc -l` -gt 0 ]; then
        EXIT_MSG='WARNING'
        EC=$WARNING
else
        EXIT_MSG='OK'
        EC=$OK
fi

#final message
NAGIOS_MSG="$EXIT_MSG - WEB Requests - Thresholds(miliseconds): Warn [$WARN_THRESHOLD] Error [$ERROR_THRESHOLD] -> REQUESTS OVER WARN [$REQ_WARN_LIST] REQUESTS OVER ERROR [$REQ_ERROR_LIST]"

#cleanup the temp file
rm /tmp/output.$$

echo $NAGIOS_MSG
exit $EC

