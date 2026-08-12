#!/bin/bash

# Description of the function of this script.

usage() {
  echo "Usage: $0 -i INPUT [-o OUTPUT]"
  echo
  echo "  -i INPUT"
  echo "    The name of the PDF file to be compacted"
  echo "  -o OUTPUT"
  echo "    The name of the compacted PDF output file."
  echo "    If omitted, the input file will be overwritten."
  exit 1
}

readargs() {
  while [ "$#" -gt 0 ] ; do
    case "$1" in
      -i)
        if [ "$2" ] ; then
          infile="$2"
          shift ; shift
        else
          echo "Missing a value for $1."
          echo
          shift
          usage
        fi
      ;;
      -o)
        if [ "$2" ] ; then
          outfile="$2"
          shift ; shift
        else
          echo "Missing a value for $1."
          echo
          shift
          usage
        fi
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
  if [ ! "${infile}" ] ; then
    echo "Missing input file."
    usage
    exit 2
  fi
}

setargs() {
  if [ ! "${outfile}" ] ; then
    outfile="${infile}"
  fi
}

checkvalues() {
#   if [ "${option}" != "option" ] ; then
#    echo "$option is not set to \"option\"."
#    usage
#   fi
  :
}

main() {
  # Enter the functional part of the script here.
  echo "Compacting: ${infile} -> ${outfile}"
  gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook -dNOPAUSE -dQUIET -dBATCH -sOutputFile="${outfile}" "${infile}"
}

readargs "$@"
checkargs
setargs
checkvalues
main
