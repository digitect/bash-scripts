#!/bin/bash

# A script to make a backup of all MySQL databases.

usage() {
  echo "Usage: $0 -u username -p password"
  echo
  echo "  -u USERNAME"
  echo "    The username to use for making the backup."
  echo "    Default: root."
  echo "  -p PASSWORD"
  echo "    The password to use in combination with the username to make the backup."
  echo "  -b BACKUPLOCATION"
  echo "    The location to store the backups to."
  echo "    Default: /tmp."
  echo "  -c"
  echo "    Indicated compression (.gz) should be used."
  echo "    Default: not set."
  exit 1
}

readargs() {
  while [ "$#" -gt 0 ] ; do
    case "$1" in
      -u)
        if [ "$2" ] ; then
          username="$2"
          shift ; shift
        else
          echo "Missing a value for $1."
          echo
          shift
          usage
        fi
      ;;
      -p)
        if [ "$2" ] ; then
          password="$2"
          shift ; shift
        else
          echo "Missing a value for $1."
          echo
          shift
          usage
        fi
      ;;
      -b)
        if [ "$2" ] ; then
          backuplocation="$2"
          shift ; shift
        else
          echo "Missing a value for $1."
          echo
          shift
          usage
        fi
      ;;
      -c)
        compression="yes"
        shift
      ;;
      *)
        echo "Unknown option or argument $1."
        echo
        shift
        usage
      ;;
    esac
  done
}

checkargs() {
#  if [ ! "${password}" ] ; then
#    echo "Missing password."
#    usage
#  fi
 :
}

setargs() {
#  if [ ! "${username}" ] ; then
#    username="root"
#  fi
  if [ ! "${backuplocation}" ] ; then
    backuplocation="/tmp"
  fi
}

checkvalues() {
  if [ ! -d "${backuplocation}" ] ; then
    echo "${backuplocation} is not a directory."
    exit 1
  fi
}

main() {
  mysql -B -N -e "show databases;" | while read database ; do
    datum=`date '+%Y-%m-%d %H:%M:%S'`
    echo -n "${datum}: Backing up mysql database for ${database}: "
    prefix=`date +%Y%m%d_%H%M`
    recent="${backuplocation}/${database}.recent"
    if [ "${compression}" ] ; then
      currentname="${prefix}_${database}.mysql.gz"
      currentbackup="${backuplocation}/${currentname}"
      mysqldump --extended-insert=FALSE ${database} | sed '$ d' | gzip -9 > ${currentbackup} 2> /dev/null
      if [ -f ${backuplocation}/${database}.recent ] ; then
        lastbackup=$(cat ${backuplocation}/${database}.recent)
        zdiff --brief ${backuplocation}/daily/${lastbackup} ${currentbackup} > /dev/null 2>&1
        if [ "$?" = 0 ] ; then
          echo "no changes for this database."
          rm ${currentbackup}
        else
          echo "moving ${currentname} to daily."
          mv ${currentbackup} ${backuplocation}/daily/
          echo "${currentname}" > ${recent}
	fi
      else
        echo "no recent file found, moving ${currentname} to daily."
        mv ${currentbackup} ${backuplocation}/daily/
        echo "${currentname}" > ${recent}
      fi
    else
      mysqldump --extended-insert=FALSE ${database} | sed '$ d' > ${backuplocation}/${prefix}_${database}.mysql 2> /dev/null
    fi
 done
}

readargs "$@"
checkargs
setargs
checkvalues
main
