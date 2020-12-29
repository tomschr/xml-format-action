#!/bin/bash
#
# Purpose:
#  Provide command line arguments to:
#  - download config file if it's a http/https address
#  - deals with include and exclude files
#
# Author: Tom Schraitle
# Date: December 2020

shopt -s extglob

# --- Global variables
ME="${0##*/}"
VERSION="0.1.0"
AUTHOR="Tom Schraitle"

# All excluded files:
EXCLUDES=()

# All files that are given by the user:
ALLXMLFILES=()

# The XML files to investigate (ALLXMLFILES - EXCLUDE):
XMLFILES=()
declare -a EXCLUDES ALLXMLFILES XMLFILES

# Use branch
BRANCH=${GITHUB_REF#*refs/heads/}


function usage {
    cat <<EOF_helptext
Usage: $ME [OPTIONS] [XMLFILES]

Options:
  -h, --help         Output this help text
  -e, --exclude      Exclude these files
  -c FILE, --config FILE
                     Pass configuration file for xmlformat.
                     If the strings starts with 'http' or 'https',
                     the config file is downloaded

Arguments:
  XMLFILES           The XML files to format

Version $VERSION, written by $AUTHOR
EOF_helptext
}



## Parsing command line arguments:
export POSIXLY_CORRECT=1
ARGS=$(getopt -o "hve:c:" -l "help,verbose,exclude:,config:" -n "$ME" -- "$@")
eval set -- "$ARGS"
unset POSIXLY_CORRECT

while true; do
    case "$1" in
    -h|--help)
        usage
        exit 1
        shift
        ;;

    -v|--verbose)
        VERBOSITY=$(($VERBOSITY+1))
        shift
        ;;

    -e|--exclude)
       EXCLUDES=( $2 )
       shift 2
       ;;

    -c|--config)
       CONFIG="$2"
       # 
       if [ -z "$CONFIG" ]; then
        echo "::error::--config variable cannot be empty"
        exit 10
       fi
       if [[ $CONFIG == http* ]]; then
          BASE=${CONFIG##*/}
          [ -e "$BASE" ] || wget --tries=2 --timeout=2 --retry-connrefused=on $CONFIG
          # Remove all paths of the URL and store the basename:
          CONFIG="${BASE}"
       elif [ ! -e "$CONFIG" ]; then
         echo "::error file=$CONFIG::File not found"
         exit 20
       fi
       
       shift 2
       ;;

    --)
        shift
        break;;

    *) exit_on_error "Internal error!" ;;
    esac
done


if [ -z "$*" ]; then
  echo "::error::No XML files found"
  exit 40
fi

# Create an array with all of our XML files:
ALLXMLFILES=($*)

# "Subtract" ALLXMLFILES from EXCLUDES to get real files
# From https://stackoverflow.com/a/2315459
for i in "${ALLXMLFILES[@]}"; do
    skip=
    for j in "${EXCLUDES[@]}"; do
        [[ $i == $j ]] && { skip=1; break; }
    done
    [[ -n $skip ]] || XMLFILES+=("$i")
done

declare -p ALLXMLFILES EXCLUDES XMLFILES
echo xmlformat ${CONFIG:+--config-file $CONFIG} --in-place "${XMLFILES[@]}"
