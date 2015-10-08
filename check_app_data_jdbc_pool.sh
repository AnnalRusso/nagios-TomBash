
#!/bin/bash
#set -x
#########################################################################
#Annalisa Russo for   #
#######################
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

#number of DB connections per DB

java -jar ${JARPATH} 'service:jmx:rmi:///jndi/rmi://localhost:'${RMIPORT}'/jmxrmi' 'com.mchange.v2.c3p0:type=PooledDataSource,identityToken=*,name=*' jdbcUrl maxPoolSize numBusyConnections | awk '{split($2, r, /\/|\?/); print r[4], $3, $4, $3-$4}' | sort -nr -k 4 > /tmp/output.$$
#echo 'database pool(max) pool(busy) pool(active)'
DB_WARN_LIST=""
DB_ERROR_LIST=""
EXIT_MSG='OK'
EC=$OK
while read line; do
        #taking out lines
        #sometimes we get <unavailable> as following "a81232_86383 40 <unavailable> 40" so we want to skip these lines
        if [ `echo $line | grep "<unavailable>" | wc -l` -gt 0 ]; then continue; fi
        if [ `echo $line | egrep "maxPoolSize|numBusyConnections" | wc -l` -gt 0 ]; then continue; fi

        DB_NAME=`echo $line | awk '{print $1}'`
        POOL_MAX=`echo $line | awk '{print $2}'`
        POOL_BUSY=`echo $line | awk '{print $3}'`
        POOL_ACTIVE=`echo $line | awk '{print $4}'`
        #echo "$DB_NAME $POOL_MAX $POOL_BUSY $POOL_ACTIVE"

        #compare with input thresholds for warning and error and generate dynamically the lists
        if [ "$POOL_BUSY" -ge "$ERROR_THRESHOLD" ]; then
                DB_ERROR_LIST=`echo $DB_ERROR_LIST $DB_NAME`
                EXIT_MSG=`echo $EXIT_MSG CRITICAL`

        elif [ "$POOL_BUSY" -ge "$WARN_THRESHOLD" ]; then
                DB_WARN_LIST=`echo $DB_WARN_LIST $DB_NAME`
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
NAGIOS_MSG="$EXIT_MSG - DB Busy Connections - Thresholds: Warn [$WARN_THRESHOLD] Error [$ERROR_THRESHOLD] -> DBs over Warn [$DB_WARN_LIST] DBs over Error [$DB_ERROR_LIST]"

#cleanup the temp file
rm /tmp/output.$$

echo $NAGIOS_MSG
exit $EC

