#!/bin/bash

# A script to make a backup of all MySQL databases.

usage() {
  echo "Usage: $0 [-p PATH] [-r REPOSITORY] [-b BACKUPLOCATION] [-c]"
  echo
  echo "  -p PATH"
  echo "    The path where the repositories are located."
  echo "    Default: /repos"
  echo "  -r REPOSITORY"
  echo "    The name of the repository to backup (without the path)."
  echo "    Default: all repositories in PATH"
  echo "  -b BACKUPLOCATION"
  echo "    The location to store the backups to."
  echo "    Default: /tmp"
  echo "  -c"
  echo "    Indicated compression (.zip) should be used."
  echo "    Default: not compressed."
  exit 1
}

readargs() {
  while [ "$#" -gt 0 ] ; do
    case "$1" in
      -p)
	if [ "$2" ] ; then
	  path="$2"
	  shift ; shift
	fi
      ;;
      -r)
        if [ "$2" ] ; then
          repository="$2"
          shift ; shift
        fi
      ;;
      -b)
        if [ "$2" ] ; then
          backuplocation="$2"
          shift ; shift
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

#checkargs() {
#  if [ ! "${repository}" ] ; then
#    echo "Missing repository."
#    echo
#    usage
#  fi
#}

setargs() {
  if [ ! "${path}" ] ; then
    path="/repos"
  fi
  if [ ! "${repository}" ] ; then
    repository="*"
  fi
  if [ ! "${backuplocation}" ] ; then
    backuplocation="/tmp"
  fi
}

checkvalues() {
  if [ ! -d "${backuplocation}" ] ; then
    echo "${backuplocation} is not a directory."
    usage
  fi
  if [ "$repository" != "*" ] ; then 
    if [ ! -d "${path}/${repository}" ] ; then       
      echo "${path}${repository} is not a valid path with repository"
      usage
    fi
  fi
}

main() {
  
  for repos in $path/$repository ; do
    echo $repos
    base=$(basename ${repos})
    revcurr=$(svnadmin verify /repos/test 2>&1 | tail -1 | sed -e 's/[^0-9]//g')
    if [ -f ${backuplocation}/${base}.recent ] ; then
      revlast=$(cat ${backuplocation}/${base}.recent)
       if [ "${revlast}" == "${revcurr}" ]; then
        echo "No changes for repository ${repos}."
      else
        echo "Repository ${repos} updated from revision ${revlast} to ${revcurr}"
        if [ "${compression}" ] ; then
          svnadmin dump ${repos} | gzip -9 > ${backuplocation}/${base}.dump.gz
        else
          svnadmin dump ${repos} > ${backuplocation}/${base}.dump
        fi
        echo "${revcurr}" > ${backuplocation}/${base}.recent
      fi
    else
      echo "No recent file found for ${repos}, last backed up revision set to 0."
      echo "0" > ${backuplocation}/${base}.recent
    fi
  done
}

readargs "$@"
#checkargs
setargs
checkvalues
main
