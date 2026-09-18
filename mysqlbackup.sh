#!/bin/bash

# A script to make a backup of all MySQL databases.

# Version, bumped on every change (see README.md). Deployments compare it with this
# repository, so a changed script without a new number shows up as a difference.
#   1.1  detect a failed mysqldump: nothing is stored, .recent is left alone, exit 1
#   1.0  dump only when changed (zdiff), skip information_schema/performance_schema
VERSION="1.1"

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

# Is dit een echte dump? Een mislukte mysqldump levert, door de pijp naar gzip, toch een
# geldig gz-bestandje van een paar bytes op. Een echte dump begint met "-- MySQL dump" of
# "-- MariaDB dump" (bij MariaDB 10.11+ op de tweede regel, na een sandbox-regel).
echte_dump() {
  if [ "${compression}" ] ; then
    zcat "$1" 2>/dev/null | head -c 300 | grep -qE -- '^-- (MySQL|MariaDB) dump'
  else
    head -c 300 "$1" 2>/dev/null | grep -qE -- '^-- (MySQL|MariaDB) dump'
  fi
}

main() {
  # Eerst de lijst ophalen en pas dan de lus in: mislukt 'show databases' (geen verbinding,
  # geen rechten), dan is dat een fout en geen stille ronde zonder databases. En de lus niet
  # als laatste schakel van een pijp, zodat 'fouten' na afloop nog bestaat.
  databases=$(mysql -B -N -e "show databases;") || { echo "ERROR: could not list the databases."; exit 1; }
  fouten=0
  while read database ; do
    # information_schema en performance_schema zijn virtuele databases: mysqldump
    # loopt er altijd op stuk met "LOCK TABLES command denied" en levert een leeg
    # bestandje van een paar honderd bytes op. Er valt niets uit terug te zetten,
    # dus overslaan in plaats van elke nacht laten mislukken.
    case "${database}" in
      information_schema|performance_schema) continue ;;
    esac
    datum=`date '+%Y-%m-%d %H:%M:%S'`
    echo -n "${datum}: Backing up mysql database for ${database}: "
    prefix=`date +%Y%m%d_%H%M`
    recent="${backuplocation}/${database}.recent"
    if [ "${compression}" ] ; then
      currentname="${prefix}_${database}.mysql.gz"
      currentbackup="${backuplocation}/${currentname}"
      mysqldump --extended-insert=FALSE ${database} | sed '$ d' | gzip -9 > ${currentbackup} 2> /dev/null
      rc=${PIPESTATUS[0]}
      # Een mislukte dump weggooien en .recent NIET bijwerken: anders vergelijkt de volgende
      # ronde met de mislukte dump, en wordt een goede dump misschien nooit meer gemaakt.
      if [ "${rc}" -ne 0 ] || ! echte_dump ${currentbackup} ; then
        echo "ERROR: dump failed (mysqldump exit code ${rc}), nothing stored."
        rm -f ${currentbackup}
        fouten=$((fouten+1))
        continue
      fi
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
      # Eerst naar een tijdelijk bestand, pas na controle op de definitieve naam.
      currentbackup="${backuplocation}/${prefix}_${database}.mysql"
      mysqldump --extended-insert=FALSE ${database} | sed '$ d' > ${currentbackup}.tmp 2> /dev/null
      rc=${PIPESTATUS[0]}
      if [ "${rc}" -ne 0 ] || ! echte_dump ${currentbackup}.tmp ; then
        echo "ERROR: dump failed (mysqldump exit code ${rc}), nothing stored."
        rm -f ${currentbackup}.tmp
        fouten=$((fouten+1))
        continue
      fi
      mv ${currentbackup}.tmp ${currentbackup}
      echo "stored ${prefix}_${database}.mysql."
    fi
  done <<< "${databases}"
  # Niet stil eindigen na een mislukte dump: de aanroeper (cron, een omhullend script)
  # moet het aan de afsluitcode kunnen zien.
  [ "${fouten}" -eq 0 ] || { echo "ERROR: ${fouten} database(s) could not be backed up."; exit 1; }
}

readargs "$@"
checkargs
setargs
checkvalues
main
