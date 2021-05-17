#!/bin/bash
#
# Purpose:
#  Investigate commit and reformat only specified XML files.
#
# Design
#   This GitHub Action can be used for push event. Any
#   pull-request events are not tested ATM.
#   As the GitHub context doesn't provide any information about
#   the pull request, its number, and their commits, we need
#   to find it through a cascade of API calls:
#
# 1. Find URL from github.event.repository.pulls_url
# 2. /commits/:sha/pulls  => gets the PR number of commit :sha
# 3. /repos/:repo/pulls/:pr/commits => gets all commits of PR :pr
# 4. Use first and last commit and create a range "first..last".
#    If there is only one commit, use first.
# 5. Use "git diff-tree" and find all files within this range
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

# The token to access the GitHub API
GH_TOKEN=""

# The JSON file containing the GitHub context:
GH_CONTEXT=""

# The default Git user and email identity
DEFAULT_USER_NAME="action"
DEFAULT_USER_EMAIL="action@github.com"


function echoerr {
  echo "::error file=xml-format-action.sh::$@"
}

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
  --token=TOKEN      The token that is used to access the GitHub API
  --context=CONTEXT_FILE
                     The GitHub context as JSON file


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

function config_user {
# Set the Git identity. If no Git identity is configured, use defaults
#
# HINT:
# This is needed, if the user forgets to configure a specific
# Git identity.
#
# Optional parameters
#   1: user, default is "actions-user"
#   2: email, default is "actions-user@users.noreply.github.com"
# Returns
#   n/a

    local user="${1:-$DEFAULT_USER_NAME}"
    local mail="${2:-$DEFAULT_USER_EMAIL}"
    local tmpuser
    local tmpmail

    tmpuser=$(git config user.name)
    if [ "" == "${tmpuser}" ]; then
        git config --global user.name "$user"
    fi
    tmpmail=$(git config user.email)
    if [ "" == "${tmpmail}" ]; then
        git config --global user.email "$mail"
    fi
}

function getxmlformat {
# Get the executable script for xmlformat.
# Depending on the distribution, it's name can be different
# (with or without extensions .rb or .pl)
#
# Parameters
#    n/a
# Returns
#    n/a; function assigns the found path to XMLFORMAT variable.

  local commands

  readarray -t commands <<< $(type -a -p xmlformat xmlformat.rb xmlformat.pl)
  XMLFORMAT=${commands[0]}
  if [ ${#XMLFORMAT} -eq 0 ]; then
    echoerr "Could not find neither of xmlformat, xmlformat.pl, nor xmlformat.rb."
    exit 10
  fi
}


function get_pr_number {
# Get the GitHub number for the last commit
#
# Parameters:
#    $1:  The SHA commit to investigate
# Returns:
#    Pull-request number
#
# See https://docs.github.com/rest/reference/repos#list-pull-requests-associated-with-a-commit
# curl -X GET -u $GITHUB_TOKEN:x-oauth-basic https://api.github.com/search/issues?q=

  local last=$1
  local commits_url
  local PR_CONTEXT="/tmp/pr-context.json"
  # last=$(jq --raw-output ".sha" $GH_CONTEXT)
  commits_url=$(jq --raw-output ".event.repository.commits_url" $GH_CONTEXT)
  # Replace {/sha} with $last/pulls
  commits_url=${commits_url//\{\/sha\}//$last/pulls}

  # Use APIv3 call to /repos/{owner}/{repo}/commits/{commit_sha}/pulls
  # https://docs.github.com/en/free-pro-team@latest/rest/reference/repos#list-pull-requests-associated-with-a-commit

  curl --silent -o $PR_CONTEXT \
   -H "Accept: application/vnd.github.groot-preview+json" \
   -u $GH_TOKEN:x-oauth-basic $commits_url

  jq --raw-output ".[].number" $PR_CONTEXT
}


function get_pr_url {
# Return github.event.repository.pulls_url from GitHub context
#
# Parameter
#   n/a
# Returns
#   URL string, with placeholder {/number}
#
# github.event.repository.pulls_url
  URL=$(jq --raw-output ".event.repository.pulls_url" $GH_CONTEXT)
  # URL=${URL//\{\/number\}/\/11}
  echo $URL
}

function get_commits_from_pr {
# Get a list of all commits from a specific pull request
#
# Parameters
#    $1  the URL to which to connect
#    $2  the pull reqest number
#
# Returns
#    a string, consists of a two SHA values separated by space:
#    "FIRST_SHA LAST_SHA"

  local URL=$1
  local PR=$2
  local PR_CONTEXT="/tmp/pr${PR}-commits.json"
  local COMMITS
  URL=${URL//\{\/number\}/\/$PR}/commits

  # /repos/:repo/pulls/:pr/commits
  # curl -o pr11-commits.json -X GET -u $GH_TOKEN:x-oauth-basic \
  # https://api.github.com/repos/tomschr/xml-format-action/pulls/11/commits
  curl --silent -o $PR_CONTEXT \
   -H "Accept: application/vnd.github.groot-preview+json" \
   -u $GH_TOKEN:x-oauth-basic -X GET $URL

  if [[ ! -e $PR_CONTEXT ]]; then
    echo "::error::Did not get output from curl."
    exit 100
  fi

  # Get first and last commit only:
  readarray -t COMMITS <<< $(jq --raw-output ".[].sha" $PR_CONTEXT | sed -e 1b -e '$!d' )
  if [ -z "${COMMITS[1]}" ]; then
    echo "${COMMITS[0]}"
  else
    echo "${COMMITS[0]}..${COMMITS[1]}"
  fi
}

function getgitfilelist {
# Get a file list of added, copied, or renamed files of a specific commit
#
# Parameters:
#    $1: the commit or commit range to investigate. A commit range
#        is separated by space
#
# Returns:
#    a sequence of files separated by space

    local RANGE="${1}"
    local FILES

    # Only look for added, copied, modified, and renamed files:
    readarray -t FILES <<< $(git diff-tree --no-commit-id --name-only -r -m --diff-filter=ACMR "$RANGE")
    # Replace newlines with spaces:
    # FILES="${FILES//$'\n'/ }"
    # Remove leading whitespace:
    # FILES="${FILES##+([[:space:]])}"
    echo ${FILES[@]}
}


getxmlformat


## Parsing command line arguments:
export POSIXLY_CORRECT=1
ARGS=$(getopt -o "hve:c:x:m:" \
       -l "help,verbose,excludes:,config-file:,extensions:,message:,need-commit:,token:,context:" -n "$ME" -- "$@")
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
            # --location follows redirects
            curl --progress-bar --location --retry-connrefused --output "$BASE" $CONFIG
            echo "Saved config to $BASE"
            ls -l $BASE
            echo "::endgroup::"
          fi
          # Use the downloaded file path:
          CONFIG="${BASE}"
       elif [[ $CONFIG == file://* ]]; then
          # Sanitize the path by removing "file://"" prefix
          CONFIG=${CONFIG#file://*}
       elif [ ! -e "$CONFIG" ]; then
         echo "::error file=$CONFIG::Configuration file not found"
         exit 20
       fi

       # At this point we have either downloaded the config file or it is
       # available elsewhere
       echo "::group::Content of $CONFIG"
       cat $CONFIG
       echo "::endgroup::"
       
       shift 2
       ;;

    --token)
       GH_TOKEN="$2"
       shift 2
       ;;

    --context)
       GH_CONTEXT="$2"
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

config_user
if [ $VERBOSITY -gt 0 ]; then
echo "::group::Git identity..."
echo "user.name=$(git config user.name)"
echo "user.email=$(git config user.email)"
echo "::endgroup::"
fi


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

# get_first_last_commits
echo "::group::Get pull request URL and PR# for commit ${COMMITSHA::7}"
URL=$(get_pr_url)
PR=$(get_pr_number $COMMITSHA)
echo "URL=$URL"
echo "PR=$PR"
echo "::endgroup::"

echo "::group::Used CLI options..."
echo "--config-file='$CONFIG'"
echo "--message='$MESSAGE'"
echo "--extensions='$EXTENSIONS'"
echo "--excludes=${EXCLUDES[@]}"
echo "--verbosity=$VERBOSITY"
echo "--need-commit=$COMMIT"
echo "--token=${GH_TOKEN:+'***'}"
echo "--context=${GH_CONTEXT}"
echo "commitsha=$COMMITSHA"
echo "::endgroup::"
fi

echo "::group::Trying to find the commits in PR#$PR..."
RANGE=$(get_commits_from_pr "$URL" "$PR")
# We check if $RANGE is empty; if yes, we assign it $COMMITSHA
# if not, we use $RANGE
# Sanitiy check: if RANGE is really empty (which shouldn't be)
# then there is something wrong.
if [ -z "$RANGE" ]; then
   echo "::warning::No range found. Using commit ${COMMITSHA::7} instead."
   RANGE="${COMMITSHA}"
fi
echo "$RANGE"
echo "::endgroup::"

if [ $VERBOSITY -gt 1 ]; then
echo "::group::GitHub context..."
ls -l "${GH_CONTEXT}"
cat ${GH_CONTEXT}
echo "::endgroup::"
fi


# Create an array with all of our XML files of the given commit:
ALLXMLFILES=( $(getgitfilelist "$RANGE") )


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
    echo $XMLFORMAT ${CONFIG:+--config-file $CONFIG} --in-place "${XMLFILES[@]}"
    $XMLFORMAT ${CONFIG:+--config-file $CONFIG} --in-place "${XMLFILES[@]}"
    echo "::endgroup::"

    echo "::group::git status"
    git status
    echo "::endgroup::"

    echo "::set-output name=xmlfound::true"
    if [ $COMMIT -eq 1 ]; then
      COMMIT_AUTHOR=$(jq ".event.commits[0].author.name" $GH_CONTEXT)
      echo "::group::Committing changed XML files..."
      cat > $FILE_COMMIT << EOF
${MESSAGE}

Co-authored-by: $COMMIT_AUTHOR <${GITHUB_ACTOR}@users.noreply.github.com>
EOF
      git commit --file="$FILE_COMMIT" "${XMLFILES[@]}" || true
      echo "::endgroup::"
      echo "::set-output name=commit::true"
    else
      echo "::set-output name=commit::false"
    fi
fi
