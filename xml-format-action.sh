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

# The command executable. Sometimes it's safed as "xmlformat"
XMLFORMAT=""

# The default commit message for reformatting the XML files:
MESSAGE="[xml-format-action] Auto reformatting XML Files"

# Filename where to add commit messages:
FILE_COMMIT="/tmp/commit-message.txt"

# The verbosity level
VERBOSITY=0

# Should the changed files committed? Default yes (=1)
COMMIT=1

# Array of all file extensions (by default "xml"):
EXTENSIONS=(xml)

# Array of all excluded files:
EXCLUDES=()

# Array of all files that are found in the specified commit:
ALLXMLFILES=()

# Array of all XML files to investigate (basically ALLXMLFILES - EXCLUDE):
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
  -m MSG, --message=MSG
                     Commit message for reformatting XML files
  --need-commit      Should the reformatted XML files committed?
                     Use "yes", 1, or "true" to do it.
                     Use "no", 0, or "false" to avoid the commit.
  -x EXT, --extensions=EXT
                     Check for extensions in file.
                     Can be used multiple times or as a single string,
                     separated by space.
                     Each extension must be specified without dots or
                     globs (default: "${EXTENSIONS[@]}").

Arguments:
  COMMIT            The commit to search for XML files. Can be a
                    40 SHA or HEAD

Examples:

  * Investigate current commit:
    $ $ME HEAD

  * Add the file extensions mml and svg to search for commit 1a3b5c7:
    $ $ME -x svg -x mml 1a3b5c7

  * Add the file extensions mml and svg, but don't format "foo.mml":
    $ $ME -x "svg mml" -e "foo.mml"

Version $VERSION, written by $AUTHOR
EOF_helptext
}

function getxmlformat {
# Get the executable script for xmlformat.
# Depending on the distribution, it's name can be different
# (with or without extension)
#
# No Parameters
# Returns the absolute path; at the same time, it assign the
# found path to XMLFORMAT variable.

  local commands

  # readarray -t commands <<< $(type -a -p xmlformat xmlformat.rb xmlformat.pl)
  commands=( $(whereis -b xmlformat | cut -d ' ' -f2) )
  XMLFORMAT=${commands[0]}
}

function get_first_last_commits {
# Get the SHAs of the first and last commit in this branch
#
# Parameters:
#   n/a
# Returns:
#
  local commits

  readarray -t commits <<< $(git rev-list --simplify-by-decoration -2 HEAD)
  echo "::group::Find last and parent commits..."
  echo "Last commit:   ${commits[0]}"
  echo "Parent commit: ${commits[1]}"
  echo "::endgroup::"
}

function getgitfilelist {
# Get a file list of added, copied, or renamed files of a specific commit
#
# Parameters:
#    $1: the commit to investigate
#
# Returns:
#    a sequence of files separated by space

    local SHA="${1}"
    local commits
    local first
    local parent

    # get the last and commit parent to the first commit of the branch (in this order)
    readarray -t commits <<< $(git rev-list --simplify-by-decoration -2 HEAD)
    last=${commits[0]}
    parent=${commits[1]}

    # Only look for added, copied, modified, and renamed files:
    FILES=$(git diff-tree --no-commit-id --name-only -r -m --diff-filter=ACMR $parent..$last)
    # Replace newlines with spaces:
    FILES="${FILES//$'\n'/ }"
    # Remove leading whitespace:
    FILES="${FILES##+([[:space:]])}"
    echo $FILES
}

getxmlformat


## Parsing command line arguments:
export POSIXLY_CORRECT=1
ARGS=$(getopt -o "hve:c:x:m:" \
       -l "help,verbose,excludes:,config-file:,extensions:,message:,need-commit:" -n "$ME" -- "$@")
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

    -m|--message)
      # Use this commit message
       MESSAGE="$2"
       shift 2
       ;;
    --need-commit)
      if [[ $2 =~ ^(0|false|no) ]]; then
          COMMIT="0"
      fi
      shift 2
      ;;

    --nocommit|--no-commit)
       COMMIT=0
       shift
       ;;
    --commit)
       COMMIT=1
       shift
       ;;
    -c|--config-file)
       CONFIG="$2"
       # 
       if [ -z "$CONFIG" ]; then
        echo "::error::--config-file option requires a value, but that was empty"
        exit 10
       fi
       if [[ $CONFIG == http* ]]; then
          # We need to save the config outside the repo so it's not accidently
          # commited.
          #
          BASE="/tmp/${CONFIG##*/}"
          if [ ! -e "$BASE" ]; then
            echo "::group::Download config file..."
            curl --progress-bar --retry-connrefused --output "$BASE" $CONFIG
            echo "::endgroup::"
          fi
          # Use the downloaded file path:
          CONFIG="${BASE}"
       elif [ ! -e "$CONFIG" ]; then
         echo "::error file=$CONFIG::Configuration file not found"
         exit 20
       fi
       
       shift 2
       ;;

    --)
        shift
        break;;

    *)
      echo "::error::Internal error!"
      echo "::error::Used CLI $*"
      exit 255
      ;;
    esac
done

# TODO: Should we check if it's HEAD or a commit hash?
# We assume a 40 length commit hash or HEAD:
COMMITSHA="$1"

if [ -z $COMMITSHA ]; then
   echo "::error::Expected commit. "
   exit 100
fi


# Make shell arrays unique as in https://stackoverflow.com/a/13648438
EXTENSIONS=($(echo "${EXTENSIONS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
EXCLUDES=($(echo "${EXCLUDES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

if [ $VERBOSITY -gt 0 ]; then
# https://docs.github.com/en/free-pro-team@latest/actions/reference/environment-variables#default-environment-variables
echo "::group::GitHub variables..."
echo "GITHUB_WORKFLOW=$GITHUB_WORKFLOW"
echo "GITHUB_EVENT_NAME=$GITHUB_EVENT_NAME"
echo "GITHUB_EVENT_PATH : $GITHUB_EVENT_PATH"
echo "GITHUB_ACTION=$GITHUB_ACTION"
echo "GITHUB_ACTOR=$GITHUB_ACTOR"
echo "GITHUB_REPOSITORY=$GITHUB_REPOSITORY"
echo "GITHUB_SHA=$GITHUB_SHA"
echo "GITHUB_HEAD_REF=$GITHUB_HEAD_REF"
echo "GITHUB_BASE_REF=$GITHUB_BASE_REF"
echo "::endgroup::"

if [ $VERBOSITY -gt 1 ]; then
echo "::group::Content of GITHUB_EVENT_PATH..."
cat $GITHUB_EVENT_PATH
echo -e "\n::endgroup::"
fi

echo "::group::xmlformat found..."
echo "$XMLFORMAT"
echo "::endgroup::"
echo "::group::Method 2 for finding xmlformat..."
readarray -t commands <<< $(type -a -p xmlformat xmlformat.rb xmlformat.pl)
echo ${commands[0]}
echo "::endgroup::"

get_first_last_commits

echo "::group::Used CLI options..."
echo "--config-file='$CONFIG'"
echo "--message='$MESSAGE'"
echo "--extensions='$EXTENSIONS'"
echo "--excludes=${EXCLUDES[@]}"
echo "--verbosity=$VERBOSITY"
echo "--need-commit=$COMMIT"
echo "commitsha=$COMMITSHA"
echo "::endgroup::"
fi


# Create an array with all of our XML files of the given commit:
ALLXMLFILES=( $(getgitfilelist $COMMITSHA) )


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
    # valid file extensions, then skip it too
    if [[ ! " ${EXTENSIONS[@]} " =~ " ${i##*.} " ]]; then
       skip=1
    fi

    # At this point, if we don't skip the file, it's an XML file
    # and we add it to our array:
    [[ -n $skip ]] || XMLFILES+=("$i")
done

echo "::group::XML files found in commit ${COMMITSHA::7}..."
echo ${ALLXMLFILES[@]}
echo "::endgroup::"


if [ $VERBOSITY -gt 0 ]; then
  echo "::group::Show shell arrays"
  declare -p ALLXMLFILES EXCLUDES EXTENSIONS XMLFILES
  echo -e "::endgroup::"
fi

if [ ${#XMLFILES[@]} -eq 0 ]; then
    echo "::warning::No XML files found in commit ${COMMITSHA::7}"
    echo "::set-output name=xmlfound::false"
else
    echo "::group::Formatting XML files..."
    $XMLFORMAT ${CONFIG:+--config-file $CONFIG} --backup .bak --in-place "${XMLFILES[@]}"
    echo "::endgroup::"
    echo "::set-output name=xmlfound::true"
    if [ $COMMIT -eq 1 ]; then
      echo "::group::Committing changed XML files..."
      cat > $FILE_COMMIT << EOF
${MESSAGE}

Co-authored-by: <${GITHUB_ACTOR}@users.noreply.github.com>
EOF
      git commit --file="$FILE_COMMIT" "${XMLFILES[@]}" || true
      echo "::endgroup::"
      echo "::set-output name=commit::true"
    else
      echo "::set-output name=commit::false"
    fi
fi
