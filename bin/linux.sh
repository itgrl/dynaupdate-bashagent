#!/usr/bin/env bash

FIRST_CALL=1
MYDIR="$( dirname ${BASH_SOURCE[0]} )"
MYDIR="${MYDIR}/../" # Moved individual scripts to bin directory so setting MYDIR to root directory.

OS=$( uname -a | cut -d ' ' -f1 )
OSDISTID=$( grep Distributor ${MYDIR}/tmp/_Linux_Standard_Base_Version_ | cut -d ':' -f 2 | tr -d ' ' )
OSRELEASE=$( grep Release ${MYDIR}/tmp/_Linux_Standard_Base_Version_ | cut -d ':' -f 2 | tr -d ' ' )
HOST=$( hostname )
MYKERNEL=$( uname -a | cut -d ' ' -f 3 )


### User Defined variables
CFG_PATH="/var/log/cfg2html/";
EXPORT_DIR="${MYDIR}/export/"
LOG_DIR="${MYDIR}/log/"

function logme(){
  # If argument is passed then log that message, otherwise log stdin
  if [ -n "$1" ]; then
    IN="$1"
  else
    read IN 
  fi
  local DateTime=$( date +%Y.%m.%d-%H:%M:%S )
  local LOGFILE="${LOG_DIR}rt-update-agent.log"
  echo "${DateTime} [$$] ${IN}" >> ${LOGFILE}
  echo "${DateTime} [$$] ${IN}"
}

function write_out(){
  local MYNAME=$1
  local MYDATA=$2
  local MYFILENAME=${HOST}.export
  if [ "${FIRST_CALL}" == 1 ]; then
    if [ ! -d "${EXPORT_DIR}" ]; then
      # If export directory does not exist, create it.
      mkdir -p ${EXPORT_DIR}
    fi
    # Initiate export file with first run
    echo "Host:::" ${HOST} > ${EXPORT_DIR}/${MYFILENAME}
    echo "OS:::" ${OS} >> ${EXPORT_DIR}/${MYFILENAME}
    echo "Distribution:::" ${OSDISTID} >> ${EXPORT_DIR}/${MYFILENAME}
    echo "Release:::" ${OSRELEASE} >> ${EXPORT_DIR}/${MYFILENAME}
    echo "Kernel:::" ${MYKERNEL} >> ${EXPORT_DIR}/${MYFILENAME}
    echo "${MYNAME}:::" ${MYDATA}  >> ${EXPORT_DIR}/${MYFILENAME}
    FIRST_CALL=0
  else
    # Append additional entries to file.
    echo "${MYNAME}:::" ${MYDATA}  >> ${EXPORT_DIR}/${MYFILENAME}
  fi	
}

function buildtmp() {
  # This function is to parse the cfg2html txt file and export the sections in 
  # the temp directory located in script source directory.
  local MYSOURCE="${CFG_PATH}${HOST}.txt"
  # Here we build the section list and write to a file for later use / reference.
  grep -e "---\=\[" "${MYSOURCE}" | cut -d'=' -f2 > ${MYDIR}/tmp/sections.txt
  
  # The IFS was changed to not split items on space into the array.
  IFS=']'
  # Populate array with sections from file.
  local MYSECTIONS=$( cat "${MYDIR}/tmp/sections.txt" )
  
  for x in ${MYSECTIONS[@]}; do
    # Looping through sections to split them out.
    xtrim=$( echo "${x}" | tr -d '\n' ) # Trim off newline characters
    x=$( echo ${xtrim} | cut -d'[' -f2 | tr -d '\n' ) # Cut out leading [
    xslash=$( echo "${x}" | sed 's/\ /\\\ /g' ) # Escape all spaces
    xslash="\\["${xslash} # Add the escaped [ back to pattern with escaped spaces

    # Replace spaces with _ to build filename
    local MYEXPORT=$( echo ${xtrim} | cut -d'[' -f2 | cut -d']' -f1 | sed 's/\ /_/g' | tr -d '\n' )
    # Split out contents from section header to start of next section header.
    ( sed -n '/'${xslash}'/{:a;n;/\[/b;p;ba}' "${MYSOURCE}" > ${MYDIR}/tmp/${MYEXPORT} ) 2>> ${MYDIR}/log/error.log

  done
  
  IFS=''
  
  # Check to see if export configuration file is present
  if [ ! -f "${MYDIR}/etc/export.conf" ]; then
    # Create the missing configuration file
    ls ${MYDIR}/tmp/ | sed 's/^/#/' | grep -v "sections.txt" > export.conf
  fi

}

function runlevel(){
  local mycurrentrunlevel=$( cut -d' ' -f2 ${MYDIR}/tmp/_current_runlevel_  )
  local myrunlevel=$( cat ${MYDIR}/tmp/_default_runlevel_ )

  write_out "Current_Run_Level" ${mycurrentrunlevel}
  write_out "Default_Run_Level" ${myrunlevel}
}

function interfaces(){
  IFS=$'\n'
  interfaces=$( ip addr | grep inet | grep -v inet6 | awk -v OFS=' ' '{if ( $7 == "secondary" ) print $8, $2; else print $7, $2}' | grep -v 127.0.0.1 )
  test=$( test ${interfaces[1]+_} && echo "array" )
  for x in $( ip addr | grep inet | grep -v inet6 | awk -v OFS=' ' '{if ( $7 == "secondary" ) print $8, $2; else print $7, $2}' | grep -v 127.0.0.1 ); do

    local interface=$( echo ${x} | cut -d ' ' -f1 | sed 's/^th/eth/')
    local ip=$( echo ${x} | cut -d ' ' -f2 | cut -d '/' -f1 )
    local mac=$( ifconfig ${interface} | grep HWaddr | cut -d' ' -f 11 )
    local netmask=$( ifconfig ${interface} | grep Mask | cut -d':' -f 4 )
    local linkspeed=$( ethtool ${interface} | grep -i "speed" | cut -d':' -f2 | tr -d ' ' )
    local duplex=$( ethtool ${interface} | grep -i "duplex" | cut -d':' -f2 | tr -d ' ' )

    # Start building interface datafile
    write_out "${interface}_interface_name" "${interface}"
    write_out "${interface}_interface_ip" "${ip}"
    write_out "${interface}_interface_mac" "${mac}"
    write_out "${interface}_interface_netmask" "${netmask}"
    write_out "${interface}_interface_linkspeed" "${linkspeed}"
    write_out "${interface}_interface_duplex" "${duplex}"    

    local mydistID=$( echo ${OSDISTID} | awk '{print tolower($0)}' )
    local myRelease=$( echo ${OSRLEASE} | awk '{print tolower($0)}' )

    if [ "${mydistID}" == "centos" ] || [ "${mydistID}" == "redhat" ]; then
      local myRelease=$( echo ${myRelease} | cut -d '.' -f1 )
      # Validate kernel version 
      if kernel_comparison $MYKERNEL; then
echo "Using lldptool"
        getlldp tool ${interface}
      elif [ "${myRelease}" -eq "5" ]; then
echo "Using lldpctl"
        getlldp ctl ${interface}
      else
        logme "Kernel version does not support LLDP lookup of ${x} switchport information."
      fi
    fi
  done
  IFS=''

}

function kernel_comparison(){

  if [ -z "${MYKERNEL}" ]; then
    logme "Kernel version not identified." 
  else
    local PART1=$( echo ${MYKERNEL} | cut -d '.' -f1 )
    local PART2=$( echo ${MYKERNEL} | cut -d '.' -f2 )
    local PART3=$( echo ${MYKERNEL} | cut -d '.' -f3 | cut -d '-' -f1 )
    if [ "${PART1}" -gt "2" ]; then
      return 0;
    elif [ "${PART1}" -eq "2" ]; then
      if [ "${PART2}" -gt "6" ]; then
        return 0;
      elif [ "${PART2}" -eq "6" ]; then
        if [ "${PART3}" -ge "26" ]; then
          return 0;
        else
          return 1;
        fi
      fi
    fi
  fi
}

function getlldp(){
  local mymethod=$1 # Which lldp utility to use
  local myint=$2 # Interface passed to this function for discovery.

  if [ "${mymethod}" == "tool" ]; then
    ( lldptool -L -i ${myint} adminStatus=rxtx ) > /dev/null
    local myportID=$( lldptool -t -n -i ${myint} -V portID | tail -n1 | cut -d ':' -f2 | tr -d ' ' )
    local myportDesc=$( lldptool -t -n -i ${myint} -V portDesc | tail -n 1 | cut -d ':' -f2 | tr -d '\t' )
    local mysysName=$( lldptool -t -n -i ${myint} -V sysName | tail -n 1 | tr -d '\t' )
    local mysysDesc=$( lldptool -t -n -i ${myint} -V sysDesc | tail -n 1 )
    local myPVID=$( lldptool -t -n -i ${myint} -V PVID | tail -n1 | cut -d ':' -f2 | tr -d ' ' )
    local myMAUtype=$( lldptool -t -n -i ${myint} -V macPhyCfg | tail -n1 | cut -d':' -f2 | tr -d ' ' )
    local myAutoNEG=$( lldptool -t -n -i ${myint} -V macPhyCfg | tail -n3 | head -n 1 | tr -d '\t' )
    local myPMDcapabilities=$( lldptool -t -n -i ${myint} -V macPhyCfg | tail -n2 | head -n 1 | cut -d ':' -f 2 | tr -d ' ' )
  elif [ "${mymethod}" == "ctl" ]; then
    lldpctl ${myint} > ${mydir}/tmp/${myint}
    local myportID=$( grep PortID ${mydir}/tmp/${myint} | cut -d ':' -f2 | tr -d ' ' | cut -d '(' -f1 )
    local myportDesc=$( grep PortDescr ${mydir}/tmp/${myint} | cut -d ':' -f2 | tr -d ' '  )
    local mysysName=$( grep SysName ${mydir}/tmp/${myint} | cut -d ':' -f2 | tr -d ' ' )
    local mysysDesc=$( grep SysDescr ${mydir}/tmp/${myint} | cut -d ':' -f2 | tr -d ' ' )
    if [[ -z "${mysysDesc}" ]]; then
      local mysysDesc=$( sed -n '/SysDescr\:/{:a;n;/Caps\:/b;p;ba}' ${mydir}/tmp/${myint} )
    fi
    local myPVID="Not Supported"
    local myMAUtype=$( grep "MAU oper type" ${mydir}/tmp/${myint} | cut -d ':' -f2  )
    local myAutoNEG=$( grep Autoneg ${mydir}/tmp/${myint} | cut -d ':' -f2 )
    local myPMDcapabilities=$( grep "PMD autoneg" ${mydir}/tmp/${myint} | cut -d ':' -f2 )
  else
    logme "Unknown lldp method for ${myint}."
  fi

  write_out "${myint}_interface_switchport" "${myportID}"
  write_out "${myint}_interface_switchport_desc" "${myportDesc}"
  write_out "${myint}_interface_switch" "${mysysName}"
  write_out "${myint}_interface_switch_description" "${mysysDesc}"
  write_out "${myint}_interface_vlan" "${myPVID}"
  write_out "${myint}_interface_MAU_type" "${myMAUtype}"
  write_out "${myint}_interface_AutoNEG" "${myAutoNEG}"
  write_out "${myint}_interface_PMD_Capabilities" "${myPMDcapabilities}"

}

function sysinfo(){
  local FQDN=$( grep -i fqdn ${MYDIR}/tmp/_uname_\&_hostname_ | cut -d '=' -f2 )
  local memory=$( cat ${MYDIR}/tmp/_Physical_Memory_ )
  local cores=$( grep "cpu cores" ${MYDIR}/tmp/_CPU_and_Model_info_ | cut -d ':' -f2 | tr -d ' ' | sort | uniq | tail -n 1 )
  local procs=$( grep "processor  " ${MYDIR}/tmp/_CPU_and_Model_info_ | cut -d ':' -f2 | tr -d ' '| tail -n 1 )  
  local physical=$( grep "physical id" ${MYDIR}/tmp/_CPU_and_Model_info_ | cut -d ':' -f2 | tr -d ' ' | sort | uniq )
  local make=$( grep "model name " ${MYDIR}/tmp/_CPU_and_Model_info_ | cut -d ':' -f2 | tr -d ' ' | uniq | cut -d '(' -f1 )
  local model=$( grep "model name " ${MYDIR}/tmp/_CPU_and_Model_info_ | cut -d ':' -f2 | tr -d ' ' | uniq | cut -d '(' -f2 | cut -d')' -f2 ); 
  # Concatentating two different lookups to bring type and model together.
  local model="${model} "$( grep "model name " ${MYDIR}/tmp/_CPU_and_Model_info_ | cut -d ':' -f2 | tr -d ' ' | uniq | cut -d')' -f3 | cut -d'@' -f1 | sed 's/CPU//' )
  local speed=$( grep "model name " ${MYDIR}/tmp/_CPU_and_Model_info_ | cut -d ':' -f2 | tr -d ' ' | uniq | cut -d '@' -f2 )
  
  # Make items human readable
  local cores=$( expr ${cores} + 1 )
  local procs=$( expr ${procs} + 1 )
  local physical=$( expr ${physical} + 1 )

  # Export data

  write_out "FQDN" "${FQDN}" 
  write_out "MEMORY" "${memory}"
  write_out "CPU_make" "${make}"
  write_out "CPU_model" "${model}"
  write_out "CPU_speed" "${speed}"
  write_out "CPU_physical" "${physical}"
  write_out "CPU_cores" "${cores}"
  write_out "CPU_processors" "${procs}"


}

function hwinfo(){  
  local mysource="${MYDIR}/tmp/_DMI_Table_Decoder_"
  function getinfo() {
    local myitem=$1
    sed -n "/${myitem}/{:a;n;/Handle/b;p;ba}" ${mysource} > ${MYDIR}/tmp/hwinfo.tmp

  } 
  
  getinfo "System\ Information"
  local myManufacturer=$( grep "Manufacturer" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 )
  local myProduct=$( grep "Product Name" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 ) 
  local myVersion=$( grep "Version" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 )
  local mySN=$( grep "Serial Number" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 )
  local myUUID=$( grep "UUID" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 | tr -d ' ' )
  local mySKU=$( grep "SKU Number" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 )
  local myFamily=$( grep "Family" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 )

  write_out "System_Manufacturer" "${myManufacturer}"
  write_out "System_Product" "${myProduct}"
  write_out "System_Version" "${myVersion}"
  write_out "System_SN" "${mySN}"
  write_out "System_UUID" "${myUUID}"
  write_out "System_SKU" "${mySKU}"

  getinfo "Chassis\ Information"
  local myManufacturer=$( grep "Manufacturer" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 )
  local myType=$( grep "Type" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 )
  local myLock=$( grep "Lock" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 )
  local myVersion=$( grep "Version" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 )
  local mySN=$( grep "Serial Number" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 )
  local myAssetTag=$( grep "Asset Tag" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 )
  local myHeight=$( grep "Height" ${MYDIR}/tmp/hwinfo.tmp | cut -d ':' -f 2 )

  write_out "Chassis_Manufacturer" "${myManufacturer}"
  write_out "Chassis_Type" "${myType}"
  write_out "Chassis_Lock" "${myLock}"
  write_out "Chassis_Version" "${myVersion}"
  write_out "Chassis_SN" "${mySN}"
  write_out "Chassis_AssetTag" "${myAssetTag}"
  write_out "Chassis_Height" "${myHeight}"

}

################################################################
## Execute the script

buildtmp # Build temporary export files
sysinfo
runlevel
hwinfo
interfaces


# EOF

