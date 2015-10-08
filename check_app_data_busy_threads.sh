#!/bin/bash
#set -x
##############################################################################################################################################################################################
#check following things in tomcat:
#number of busy threads,
#Put them into all application servers. Checks must have following switches
#-w number (if over issue warning)
#-e number(if over issue error)
#########################################################################
#AnnalRu       #
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

#number of busy threads
JMXQUERY=$(java -jar ${JARPATH} 'service:jmx:rmi:///jndi/rmi://localhost:'${RMIPORT}'/jmxrmi' 'Catalina:type=ThreadPool,name="ajp-bio-'$AJPBIO'"' currentThreadsBusy maxThreads)
#echo $JMXQUERY
result=($JMXQUERY)
currentThreadsBusy=${result[4]}
maxThreads=${result[5]}
#echo "currentThreadsBusy [$currentThreadsBusy] maxThreads [$maxThreads]"

#compare with input thresholds for warning and error
if [ "$currentThreadsBusy" -ge "$maxThreads" ]; then
        echo CRITICAL - Tomcat current busy threads ${result[4]} reached Maximum configured threads ${result[5]};
        exit $CRITICAL

elif [ "$currentThreadsBusy" -ge "$ERROR_THRESHOLD" ]; then
        echo CRITICAL - Tomcat current busy threads ${result[4]} is greater than the passed Error threshold ${result[5]};
        exit $CRITICAL

elif [ "$currentThreadsBusy" -ge "$WARN_THRESHOLD" ]; then
        echo WARNING - Tomcat current busy threads ${result[4]} is greater than the passed Warning threshold ${result[5]};
        exit $WARNING
else
        echo OK - Tomcat current busy threads ${result[4]} - maxThreads ${result[5]};
        exit $OK
fi

