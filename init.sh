#!/usr/bin/env sh

OS=`uname -a | cut -d ' ' -f1` 
HOST=`hostname` 
MYKERNEL=`uname -a | cut -d ' ' -f 3` 
NOTIFY_ME="PDLNASOHPL@ex1.eamcs.ericsson.se"
MYDIR=`dirname $0` 

if [ ${OS} = "Linux" ]; then
  sh ${MYDIR}/bin/linux.sh
elif [ ${OS} = "HP-UX" ]; then
  sh ${MYDIR}/bin/hpux.sh
elif [ ${OS} = "SunOS" ]; then
  sh ${MYDIR}/bin/sunos.sh
else
  echo " I don't know you, ${OS}!" | mail -s ${HOST} ${NOTIFY_ME}
fi
