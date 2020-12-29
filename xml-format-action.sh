#!/bin/bash
#
# Purpose:
#  Investigate commit and reformat only specified XML files.
#
# Author: Tom Schraitle
# Date: December 2020

shopt -s extglob

# --- Global variables
ME="${0##*/}"
VERSION="0.1.0"
AUTHOR="Tom Schraitle"

VERBOSITY=0

# All file extensions (by default "xml"):
EXTENSIONS=(xml)

# All excluded files:
EXCLUDES=()

# All files that are found in the specified commit:
ALLXMLFILES=()

# The XML files to investigate (ALLXMLFILES - EXCLUDE):
XMLFILES=()


function usage {
    cat <<EOF_helptext
Usage: $ME [OPTIONS] <COMMIT>

Investigates commit and reformat only specified XML files.

Options:
  -h, --help         Output this help text
  -e FILES, --exclude=FILES
                     Exclude these files.
                     Can be used multiple times or as a single string,
                     separated by space.
  -c FILE, --config-file=FILE
                     Pass configuration file for xmlformat.
                     If the strings starts with 'http' or 'https',
                     the config file is downloaded
  -x EXT, --extensions=EXT
                     Check for extensions in file.
                     Can be used multiple times or as a single string,
                     separated by space.
                     Each extension must be specified without dots or
                     globs (default: "${EXTENSIONS[@]}").

Arguments:
  COMMIT             The commit to search for XML files.

Examples:

  * Investigate current commit (=HEAD):
    $ $ME HEAD

  * Add the file extensions mml and svg to search for commit 1234567:
    $ $ME -x svg -x mml 1234567

  * Add the file extensions mml and svg, but don't format "foo.mml":
    $ $ME -x "svg mml" -e "foo.mml"

Version $VERSION, written by $AUTHOR
EOF_helptext
}


function getgitfilelist {
# Get a file list of added, copied, or renamed files of a specific commit
#
# Parameters:
#    $1: the commit to investigate
#
# Returns:
#    a sequence of files separated by space

    local COMMIT="${1}"
    # Only look for added, copied, modified, and renamed files:
    FILES=$(git diff-tree --no-commit-id --name-only -r -m --diff-filter=ACMR $COMMIT)
    # Replace newlines with spaces:
    FILES="${FILES//$'\n'/ }"
    # Remove leading whitespace:
    FILES="${FILES##+([[:space:]])}"
    echo $FILES
}

## Parsing command line arguments:
export POSIXLY_CORRECT=1
ARGS=$(getopt -o "hve:c:x:" -l "help,verbose,excludes:,config-file:,extensions:" -n "$ME" -- "$@")
eval set -- "$ARGS"
unset POSIXLY_CORRECT

echo "::warning::Command line: $*"

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

    -e|--excludes)
       # Prevent from adding empty strings
       if [ ! -z "$2" ]; then
          EXCLUDES+=($2)
       fi
       shift 2
       ;;

    -x|--extensions)
       # Prevent from adding empty strings
       if [ ! -z "$2" ]; then
          EXTENSIONS+=($2)
       fi
       shift 2
       ;;

    -c|--config-file)
       CONFIG="$2"
       # 
       if [ -z "$CONFIG" ]; then
        echo "::error::--config option requires a value, but that was empty"
        exit 10
       fi
       if [[ $CONFIG == http* ]]; then
          # We need to save the config outside the repo so it's not accidently
          # commited.
          #
          BASE="/tmp/${CONFIG##*/}"
          echo "::group::Download config file..."
          [ -e "$BASE" ] || wget -O "$BASE" --tries=2 --timeout=2 --retry-connrefused=on $CONFIG
          echo -e "::endgroup::"
          # Use the downloaded file path:
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

    *)
      echo "::error::Internal error!"
      echo "::error::Used $*"
      exit 255
      ;;
    esac
done

COMMIT="$1"

if [ -z $COMMIT ]; then
   echo "::error::Expected commit. "
   exit 100
fi

# Make shell arrays unique as in https://stackoverflow.com/a/13648438
EXTENSIONS=($(echo "${EXTENSIONS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
EXCLUDES=($(echo "${EXCLUDES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

[ $VERBOSITY -gt 0 ] && echo "Use commit $COMMIT"

# Create an array with all of our XML files of the given commit:
ALLXMLFILES=( $(getgitfilelist $COMMIT) )


# "Subtract" ALLXMLFILES from EXCLUDES to get real files
# From https://stackoverflow.com/a/2315459
for i in "${ALLXMLFILES[@]}"; do
    skip=
    # First, check if the file is in the exclude list.
    # If yes, skip, otherwise continue.
    for j in "${EXCLUDES[@]}"; do
        [[ $i == $j ]] && { skip=1; break; }
    done

    # Second, if the file extension is NOT in the list of
    # valid file extensions, then skip it
    if [[ ! " ${EXTENSIONS[@]} " =~ " ${i##*.} " ]]; then
       skip=1
    fi

    [[ -n $skip ]] || XMLFILES+=("$i")
done


if [ $VERBOSITY -gt 0 ]; then
  echo "::group::Show shell arrays"
  declare -p ALLXMLFILES EXCLUDES EXTENSIONS XMLFILES
  echo -e "::endgroup::"
fi

if [ ${#XMLFILES[@]} -eq 0 ]; then
    echo "::warning::No XML files found in commit $COMMIT"
else
    xmlformat ${CONFIG:+--config-file $CONFIG} --backup .bak --in-place "${XMLFILES[@]}"
fi
