#!/usr/bin/env bash

# the dir that this script resides in
dir=$(dirname $BASH_SOURCE)

source $dir/prompt-colors.sh
source $dir/themes/default

function async_run {
  echo "async_run called" >> /tmp/gitp.log
  {
    eval "$@" &> /dev/null
  }&
}

function git_prompt_dir {
  echo "git_prompt_dir called" >> /tmp/gitp.log
  # assume the gitstatus.sh is in the same directory as this script
  # code thanks to http://stackoverflow.com/questions/59895
  if [ -z "$__GIT_PROMPT_DIR" ]; then
    local SOURCE="${BASH_SOURCE[0]}"
    while [ -h "$SOURCE" ]; do
      local DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
      SOURCE="$(readlink "$SOURCE")"
      [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
    done
    __GIT_PROMPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  fi
}

# gp_set_file_var ENVAR SOMEFILE
#
# If ENVAR is set, check that it's value exists as a readable file.  Otherwise,
# Set ENVAR to the path to SOMEFILE, based on $HOME, $__GIT_PROMPT_DIR, and the
# directory of the current script.  The SOMEFILE can be prefixed with '.', or
# not.
#
# Return 0 (success) if ENVAR not already defined, 1 (failure) otherwise.

function gp_set_file_var {
  echo "gp_set_file_var called" >> /tmp/gitp.log
  local envar="$1"
  local file="$2"
  if eval "[[ -n \"\$$envar\" && -r \"\$$envar\" ]]" ; then # is envar set to a readable file?
    local basefile
    eval "basefile=\"\`basename \\\"\$$envar\\\"\`\""   # assign basefile
    if [[ "$basefile" = "$file" || "$basefile" = ".$file" ]]; then
      return 0
    fi
  else  # envar is not set, or it's set to a different file than requested
    eval "$envar="      # set empty envar
    gp_maybe_set_envar_to_path "$envar" "$HOME/.$file" "$HOME/$file" "$HOME/lib/$file" && return 0
    git_prompt_dir
    gp_maybe_set_envar_to_path "$envar" "$__GIT_PROMPT_DIR/$file" "${0##*/}/$file"     && return 0
  fi
  return 1
}

# gp_maybe_set_envar_to_path ENVAR FILEPATH ...
#
# return 0 (true) if any FILEPATH is readable, set ENVAR to it
# return 1 (false) if not

function gp_maybe_set_envar_to_path {
  echo "gp_maybe_set_envar_to_path called" >> /tmp/gitp.log
  local envar="$1"
  shift
  local file
  for file in "$@" ; do
    if [[ -r "$file" ]]; then
      eval "$envar=\"$file\""
      return 0
    fi
  done
  return 1
}

# git_prompt_reset
#
# unsets selected GIT_PROMPT variables, causing the next prompt callback to
# recalculate them from scratch.

git_prompt_reset() {
  local var
  for var in GIT_PROMPT_DIR __GIT_PROMPT_COLORS_FILE __PROMPT_COLORS_FILE __GIT_STATUS_CMD GIT_PROMPT_THEME_NAME; do
    unset $var
  done
}

# gp_format_exit_status RETVAL
#
# echos the symbolic signal name represented by RETVAL if the process was
# signalled, otherwise echos the original value of RETVAL

gp_format_exit_status() {
  local RETVAL="$1"
  local SIGNAL
  # Suppress STDERR in case RETVAL is not an integer (in such cases, RETVAL
  # is echoed verbatim)
  if [ "${RETVAL}" -gt 128 ] 2>/dev/null; then
    SIGNAL=$(( ${RETVAL} - 128 ))
    kill -l "${SIGNAL}" 2>/dev/null || echo "${RETVAL}"
  else
    echo "${RETVAL}"
  fi
}

function git_prompt_config {
  _isroot=false
  [[ $UID -eq 0 ]] && _isroot=true

  if is_function prompt_callback; then
    prompt_callback="prompt_callback"
  else
    prompt_callback="prompt_callback_default"
  fi

  if [[ "$GIT_PROMPT_LAST_COMMAND_STATE" = "0" ]]; then
    LAST_COMMAND_INDICATOR="$GIT_PROMPT_COMMAND_OK";
  else
    LAST_COMMAND_INDICATOR="$GIT_PROMPT_COMMAND_FAIL";
  fi

  # replace _LAST_COMMAND_STATE_ token with the actual state
  GIT_PROMPT_LAST_COMMAND_STATE=$(gp_format_exit_status ${GIT_PROMPT_LAST_COMMAND_STATE})
  LAST_COMMAND_INDICATOR="${LAST_COMMAND_INDICATOR//_LAST_COMMAND_STATE_/${GIT_PROMPT_LAST_COMMAND_STATE}}"

  # Do this only once to define PROMPT_START and PROMPT_END

  if [[ -z "$PROMPT_START" || -z "$PROMPT_END" ]]; then

    if [[ -z "$GIT_PROMPT_START" ]] ; then
      if $_isroot; then
        PROMPT_START="$GIT_PROMPT_START_ROOT"
      else
        PROMPT_START="$GIT_PROMPT_START_USER"
      fi
    else
      PROMPT_START="$GIT_PROMPT_START"
    fi

    if [[ -z "$GIT_PROMPT_END" ]] ; then
      if $_isroot; then
        PROMPT_END="$GIT_PROMPT_END_ROOT"
      else
        PROMPT_END="$GIT_PROMPT_END_USER"
      fi
    else
      PROMPT_END="$GIT_PROMPT_END"
    fi
  fi

  # set GIT_PROMPT_LEADING_SPACE to 0 if you want to have no leading space in front of the GIT prompt
  if [[ "$GIT_PROMPT_LEADING_SPACE" = 0 ]]; then
    PROMPT_LEADING_SPACE=""
  else
    PROMPT_LEADING_SPACE=" "
  fi

  if [[ "$GIT_PROMPT_ONLY_IN_REPO" = 1 ]]; then
    EMPTY_PROMPT="$OLD_GITPROMPT"
  else
    local ps="$(gp_add_virtualenv_to_prompt)$PROMPT_START$($prompt_callback)$PROMPT_END"
    EMPTY_PROMPT="${ps//_LAST_COMMAND_INDICATOR_/${LAST_COMMAND_INDICATOR}}"
  fi

  # fetch remote revisions every other $GIT_PROMPT_FETCH_TIMEOUT (default 5) minutes
  if [[ -z "$GIT_PROMPT_FETCH_TIMEOUT" ]]; then
    GIT_PROMPT_FETCH_TIMEOUT="5"
  fi

  if [[ -z "$__GIT_STATUS_CMD" ]] ; then          # if GIT_STATUS_CMD not defined..
    git_prompt_dir
    if ! gp_maybe_set_envar_to_path __GIT_STATUS_CMD "$__GIT_PROMPT_DIR/$GIT_PROMPT_STATUS_COMMAND" ; then
      echo 1>&2 "Cannot find $GIT_PROMPT_STATUS_COMMAND!"
    fi
    # __GIT_STATUS_CMD defined
  fi

  unset GIT_BRANCH
}

function setLastCommandState {
  echo "setLastCommandState called" >> /tmp/gitp.log
  GIT_PROMPT_LAST_COMMAND_STATE=$?
}

function we_are_on_repo {
  echo "we_are_on_repo called" >> /tmp/gitp.log
  if [[ -e "$(git rev-parse --git-dir 2> /dev/null)" ]]; then
    echo 1
    return
  fi
  echo 0
}

function update_old_git_prompt {
  echo "update_old_git_prompt called" >> /tmp/gitp.log
  local in_repo=$(we_are_on_repo)
  if [[ $GIT_PROMPT_OLD_DIR_WAS_GIT = 0 ]]; then
    OLD_GITPROMPT=$PS1
  fi

  GIT_PROMPT_OLD_DIR_WAS_GIT=$in_repo
}

function setGitPrompt {
  echo "setGitPrompt called" >> /tmp/gitp.log
  update_old_git_prompt

  local repo=$(git rev-parse --show-toplevel 2> /dev/null)
  if [[ ! -e "$repo" ]] && [[ "$GIT_PROMPT_ONLY_IN_REPO" = 1 ]]; then
    # we do not permit bash-git-prompt outside git repos, so nothing to do
#    PS1="$OLD_GITPROMPT"
    return
  fi

  local EMPTY_PROMPT
  local __GIT_STATUS_CMD

  git_prompt_config

  if [[ ! -e "$repo" ]] || [[ "$GIT_PROMPT_DISABLE" = 1 ]]; then
#    PS1="$EMPTY_PROMPT"
    return
  fi

  local FETCH_REMOTE_STATUS=1
  if [[ "$GIT_PROMPT_FETCH_REMOTE_STATUS" = 0 ]]; then
    FETCH_REMOTE_STATUS=0
  fi

  unset GIT_PROMPT_IGNORE
  OLD_GIT_PROMPT_SHOW_UNTRACKED_FILES=${GIT_PROMPT_SHOW_UNTRACKED_FILES}
  unset GIT_PROMPT_SHOW_UNTRACKED_FILES

  OLD_GIT_PROMPT_IGNORE_SUBMODULES=${GIT_PROMPT_IGNORE_SUBMODULES}
  unset GIT_PROMPT_IGNORE_SUBMODULES

  if [[ -e "$repo/.bash-git-rc" ]]; then
    # The config file can only contain variable declarations on the form A_B=0 or G_P=all
    local CONFIG_SYNTAX="^(FETCH_REMOTE_STATUS|GIT_PROMPT_SHOW_UNTRACKED_FILES|GIT_PROMPT_IGNORE_SUBMODULES|GIT_PROMPT_IGNORE)=[0-9a-z]+$"
    if egrep -q -v "$CONFIG_SYNTAX" "$repo/.bash-git-rc"; then
      echo ".bash-git-rc can only contain variable values on the form NAME=value. Ignoring file." >&2
    else
      source "$repo/.bash-git-rc"
    fi
  fi

  if [ -z "${GIT_PROMPT_SHOW_UNTRACKED_FILES}" ]; then
    GIT_PROMPT_SHOW_UNTRACKED_FILES=${OLD_GIT_PROMPT_SHOW_UNTRACKED_FILES}
  fi
  unset OLD_GIT_PROMPT_SHOW_UNTRACKED_FILES

  if [ -z "${GIT_PROMPT_IGNORE_SUBMODULES}" ]; then
    GIT_PROMPT_IGNORE_SUBMODULES=${OLD_GIT_PROMPT_IGNORE_SUBMODULES}
  fi
  unset OLD_GIT_PROMPT_IGNORE_SUBMODULES

  if [[ "$GIT_PROMPT_IGNORE" = 1 ]]; then
#    PS1="$EMPTY_PROMPT"
    return
  fi

  if [[ "$FETCH_REMOTE_STATUS" = 1 ]]; then
    checkUpstream
  fi

  updatePrompt
}

function olderThanMinutes {
  local matches
  local find_exit_code

  matches=$(find "$1" -mmin +"$2" 2> /dev/null)
  echo "find "$1" -mmin +"$2" 2> /dev/null" >> /tmp/gitp_maches.log
  if [[ -n "$matches" ]]; then
    return 0
  else
    return 1
  fi

}

function checkUpstream {
  local GIT_PROMPT_FETCH_TIMEOUT
  git_prompt_config

  local FETCH_HEAD="$repo/.git/FETCH_HEAD"
  # Fech repo if local is stale for more than $GIT_FETCH_TIMEOUT minutes
  if [[ ! -e "$FETCH_HEAD" ]] || olderThanMinutes "$FETCH_HEAD" "$GIT_PROMPT_FETCH_TIMEOUT"
  then
    if [[ -n $(git remote show) ]]; then
      (
        GIT_TERMINAL_PROMPT=0 git fetch --quiet > /dev/null &
        disown -h
      )
    fi
  fi
}

function checkUpstream {
  echo "checkUpstream called" >> /tmp/gitp.log
  local GIT_PROMPT_FETCH_TIMEOUT
  git_prompt_config

  local FETCH_HEAD="$repo/.git/FETCH_HEAD"
  # Fech repo if local is stale for more than $GIT_FETCH_TIMEOUT minutes
  if [[ ! -e "$FETCH_HEAD" ]]  \
     || olderThanMinutes "$FETCH_HEAD" "$GIT_PROMPT_FETCH_TIMEOUT"  \
     && [[ -n $(git remote show) ]];
  then
    git fetch --quiet /dev/null 2>&1 &
  fi
}

function replaceSymbols {
  echo "replaceSymbols called" >> /tmp/gitp.log
  # Disable globbing, so a * could be used as symbol here
  set -f

  if [[ -z ${GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING} ]]; then
    GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING=L
  fi

  local VALUE=${1//_AHEAD_/${GIT_PROMPT_SYMBOLS_AHEAD}}
  local VALUE1=${VALUE//_BEHIND_/${GIT_PROMPT_SYMBOLS_BEHIND}}
  local VALUE2=${VALUE1//_NO_REMOTE_TRACKING_/${GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING}}

  echo ${VALUE2//_PREHASH_/${GIT_PROMPT_SYMBOLS_PREHASH}}

  # reenable globbing symbols
  set +f
}

function createPrivateIndex {
  echo "createPrivateIndex called" >> /tmp/gitp.log
  # Create a copy of the index to avoid conflicts with parallel git commands, e.g. git rebase.
  local __GIT_INDEX_FILE
  local __GIT_INDEX_PRIVATE
  if [[ -z "$GIT_INDEX_FILE" ]]; then
    __GIT_INDEX_FILE="$(git rev-parse --git-dir)/index"
  else
    __GIT_INDEX_FILE="$GIT_INDEX_FILE"
  fi
  __GIT_INDEX_PRIVATE="/tmp/git-index-private$$"
  command cp "$__GIT_INDEX_FILE" "$__GIT_INDEX_PRIVATE" 2>/dev/null
  echo "$__GIT_INDEX_PRIVATE"
}

function updatePrompt {
  echo "updatePrompt called" >> /tmp/gitp.log
  local LAST_COMMAND_INDICATOR
  local PROMPT_LEADING_SPACE
  local PROMPT_START
  local PROMPT_END
  local EMPTY_PROMPT
  local Blue="\[\033[0;34m\]"

  git_prompt_config

  export __GIT_PROMPT_IGNORE_STASH=${GIT_PROMPT_IGNORE_STASH}
  export __GIT_PROMPT_SHOW_UPSTREAM=${GIT_PROMPT_SHOW_UPSTREAM}
  export __GIT_PROMPT_IGNORE_SUBMODULES=${GIT_PROMPT_IGNORE_SUBMODULES}

  if [ -z "${GIT_PROMPT_SHOW_UNTRACKED_FILES}" ]; then
    export __GIT_PROMPT_SHOW_UNTRACKED_FILES=all
  else
    export __GIT_PROMPT_SHOW_UNTRACKED_FILES=${GIT_PROMPT_SHOW_UNTRACKED_FILES}
  fi

  if [ -z "${GIT_PROMPT_SHOW_CHANGED_FILES_COUNT}" ]; then
    export __GIT_PROMPT_SHOW_CHANGED_FILES_COUNT=1
  else
    export __GIT_PROMPT_SHOW_CHANGED_FILES_COUNT=${GIT_PROMPT_SHOW_CHANGED_FILES_COUNT}
  fi

  local GIT_INDEX_PRIVATE="$(createPrivateIndex)"
  #important to define GIT_INDEX_FILE as local: This way it only affects this function (and below) - even with the export afterwards
  local GIT_INDEX_FILE
  export GIT_INDEX_FILE="$GIT_INDEX_PRIVATE"

  local -a git_status_fields
  git_status_fields=($("$__GIT_STATUS_CMD" 2>/dev/null))
  echo "$__GIT_STATUS_CMD" >> /tmp/gitp_cmd.log
  
  printf '%s\n' "${git_status_fields[@]}" > /tmp/gitp_fields.log

  export GIT_BRANCH=$(replaceSymbols ${git_status_fields[0]})
  local GIT_REMOTE="$(replaceSymbols ${git_status_fields[1]})"
  if [[ "." == "$GIT_REMOTE" ]]; then
    unset GIT_REMOTE
  fi

  local GIT_UPSTREAM_PRIVATE="${git_status_fields[2]}"
  if [[ -z "${__GIT_PROMPT_SHOW_UPSTREAM}" || "^" == "$GIT_UPSTREAM_PRIVATE" ]]; then
    unset GIT_UPSTREAM
  else
    export GIT_UPSTREAM=${GIT_UPSTREAM_PRIVATE}
    local GIT_FORMATTED_UPSTREAM="${GIT_PROMPT_UPSTREAM//_UPSTREAM_/\$GIT_UPSTREAM}"
  fi

  local GIT_STAGED=${git_status_fields[3]}
  local GIT_CONFLICTS=${git_status_fields[4]}
  local GIT_CHANGED=${git_status_fields[5]}
  local GIT_UNTRACKED=${git_status_fields[6]}
  local GIT_STASHED=${git_status_fields[7]}
  local GIT_CLEAN=${git_status_fields[8]}

  local NEW_PROMPT="$EMPTY_PROMPT"
  if [[ -n "$git_status_fields" ]]; then

    case "$GIT_BRANCH" in
      $GIT_PROMPT_MASTER_BRANCHES)
        local STATUS_PREFIX="${PROMPT_LEADING_SPACE}${GIT_PROMPT_PREFIX}${GIT_PROMPT_MASTER_BRANCH}\${GIT_BRANCH}${ResetColor}${GIT_FORMATTED_UPSTREAM}"
        ;;
      *)
        local STATUS_PREFIX="${PROMPT_LEADING_SPACE}${GIT_PROMPT_PREFIX}${GIT_PROMPT_BRANCH}\${GIT_BRANCH}${ResetColor}${GIT_FORMATTED_UPSTREAM}"
        ;;
    esac
    local STATUS=""

    # __add_status KIND VALEXPR INSERT
    # eg: __add_status  'STAGED' '-ne 0'

    __chk_gitvar_status() {
      local v
      if [[ "x$2" == "x-n" ]] ; then
        v="$2 \"\$GIT_$1\""
      else
        v="\$GIT_$1 $2"
      fi
      if eval "test $v" ; then
        if [[ $# -lt 2 || "$3" != '-' ]] && [[ "x$__GIT_PROMPT_SHOW_CHANGED_FILES_COUNT" == "x1" || "x$1" == "xREMOTE" ]]; then
          __add_status "\$GIT_PROMPT_$1\$GIT_$1\$ResetColor"
        else
          __add_status "\$GIT_PROMPT_$1\$ResetColor"
        fi
      fi
    }

    __add_gitvar_status() {
      __add_status "\$GIT_PROMPT_$1\$GIT_$1\$ResetColor"
    }

    # __add_status SOMETEXT
    __add_status() {
      eval "STATUS=\"$STATUS$1\""
    }

    __chk_gitvar_status 'REMOTE'     '-n'
    if [[ $GIT_CLEAN -eq 0 ]] || [[ $GIT_PROMPT_CLEAN != "" ]]; then
      __add_status        "$GIT_PROMPT_SEPARATOR"
      __chk_gitvar_status 'STAGED'     '!= "0" -a $GIT_STAGED != "^"'
      __chk_gitvar_status 'CONFLICTS'  '!= "0"'
      __chk_gitvar_status 'CHANGED'    '!= "0"'
      __chk_gitvar_status 'UNTRACKED'  '!= "0"'
      __chk_gitvar_status 'STASHED'    '!= "0"'
      __chk_gitvar_status 'CLEAN'      '= "1"'   -
    fi
    __add_status        "$ResetColor$GIT_PROMPT_SUFFIX"

    NEW_PROMPT="$(gp_add_virtualenv_to_prompt)$PROMPT_START$($prompt_callback)$STATUS_PREFIX$STATUS$PROMPT_END"
  else
    NEW_PROMPT="$EMPTY_PROMPT"
  fi
  
  # don't change or output anything ... the internal workings need this function for something 
  # so let it do it's thing but don't take any actions
  #PS1="${NEW_PROMPT//_LAST_COMMAND_INDICATOR_/${LAST_COMMAND_INDICATOR}${ResetColor}}"

  command rm "$GIT_INDEX_PRIVATE" 2>/dev/null
}


function omg {
  local LAST_COMMAND_INDICATOR
  local PROMPT_LEADING_SPACE
  local PROMPT_START
  local PROMPT_END
  local EMPTY_PROMPT
  local Blue="\[\033[0;34m\]"

  git_prompt_config

  export __GIT_PROMPT_IGNORE_STASH=${GIT_PROMPT_IGNORE_STASH}
  export __GIT_PROMPT_SHOW_UPSTREAM=${GIT_PROMPT_SHOW_UPSTREAM}
  export __GIT_PROMPT_IGNORE_SUBMODULES=${GIT_PROMPT_IGNORE_SUBMODULES}

  if [ -z "${GIT_PROMPT_SHOW_UNTRACKED_FILES}" ]; then
    export __GIT_PROMPT_SHOW_UNTRACKED_FILES=all
  else
    export __GIT_PROMPT_SHOW_UNTRACKED_FILES=${GIT_PROMPT_SHOW_UNTRACKED_FILES}
  fi

  if [ -z "${GIT_PROMPT_SHOW_CHANGED_FILES_COUNT}" ]; then
    export __GIT_PROMPT_SHOW_CHANGED_FILES_COUNT=1
  else
    export __GIT_PROMPT_SHOW_CHANGED_FILES_COUNT=${GIT_PROMPT_SHOW_CHANGED_FILES_COUNT}
  fi

  local GIT_INDEX_PRIVATE="$(createPrivateIndex)"
  #important to define GIT_INDEX_FILE as local: This way it only affects this function (and below) - even with the export afterwards
  local GIT_INDEX_FILE
  export GIT_INDEX_FILE="$GIT_INDEX_PRIVATE"

  local -a git_status_fields
  #gsf=$git_status_fields
  git_status_fields=($("$__GIT_STATUS_CMD" 2>/dev/null))
  

  export GIT_BRANCH=$(replaceSymbols ${git_status_fields[0]})
  local GIT_REMOTE="$(replaceSymbols ${git_status_fields[1]})"
  if [[ "." == "$GIT_REMOTE" ]]; then
    unset GIT_REMOTE
  fi

  local GIT_UPSTREAM_PRIVATE="${git_status_fields[2]}"
  if [[ -z "${__GIT_PROMPT_SHOW_UPSTREAM}" || "^" == "$GIT_UPSTREAM_PRIVATE" ]]; then
    unset GIT_UPSTREAM
  else
    export GIT_UPSTREAM=${GIT_UPSTREAM_PRIVATE}
    local GIT_FORMATTED_UPSTREAM="${GIT_PROMPT_UPSTREAM//_UPSTREAM_/\$GIT_UPSTREAM}"
  fi

  local GIT_STAGED=${git_status_fields[3]}
  local GIT_CONFLICTS=${git_status_fields[4]}
  local GIT_CHANGED=${git_status_fields[5]}
  local GIT_UNTRACKED=${git_status_fields[6]}
  local GIT_STASHED=${git_status_fields[7]}
  local GIT_CLEAN=${git_status_fields[8]}

  local NEW_PROMPT="$EMPTY_PROMPT"
  if [[ -n "$git_status_fields" ]]; then

    case "$GIT_BRANCH" in
      $GIT_PROMPT_MASTER_BRANCHES)
        local STATUS_PREFIX="${PROMPT_LEADING_SPACE}${GIT_PROMPT_PREFIX}${GIT_PROMPT_MASTER_BRANCH}\${GIT_BRANCH}${ResetColor}${GIT_FORMATTED_UPSTREAM}"
        ;;
      *)
        local STATUS_PREFIX="${PROMPT_LEADING_SPACE}${GIT_PROMPT_PREFIX}${GIT_PROMPT_BRANCH}\${GIT_BRANCH}${ResetColor}${GIT_FORMATTED_UPSTREAM}"
        ;;
    esac
    local STATUS=""

    # __add_status KIND VALEXPR INSERT
    # eg: __add_status  'STAGED' '-ne 0'

    __chk_gitvar_status() {
      local v
      if [[ "x$2" == "x-n" ]] ; then
        v="$2 \"\$GIT_$1\""
      else
        v="\$GIT_$1 $2"
      fi
      if eval "test $v" ; then
        if [[ $# -lt 2 || "$3" != '-' ]] && [[ "x$__GIT_PROMPT_SHOW_CHANGED_FILES_COUNT" == "x1" || "x$1" == "xREMOTE" ]]; then
          __add_status "\$GIT_PROMPT_$1\$GIT_$1\$ResetColor"
        else
          __add_status "\$GIT_PROMPT_$1\$ResetColor"
        fi
      fi
    }
    
    __add_gitvar_status() {
      __add_status "\$GIT_PROMPT_$1\$GIT_$1\$ResetColor"
    }

    # __add_status SOMETEXT
    __add_status() {
      eval "STATUS=\"$STATUS$1\""
    }

    __chk_gitvar_status 'REMOTE'     '-n'
    if [[ $GIT_CLEAN -eq 0 ]] || [[ $GIT_PROMPT_CLEAN != "" ]]; then
      __add_status        "$GIT_PROMPT_SEPARATOR"
      __chk_gitvar_status 'STAGED'     '!= "0" -a $GIT_STAGED != "^"'
      __chk_gitvar_status 'CONFLICTS'  '!= "0"'
      __chk_gitvar_status 'CHANGED'    '!= "0"'
      __chk_gitvar_status 'UNTRACKED'  '!= "0"'
      __chk_gitvar_status 'STASHED'    '!= "0"'
      __chk_gitvar_status 'CLEAN'      '= "1"'   -
    fi
    __add_status        "$ResetColor$GIT_PROMPT_SUFFIX"

    NEW_PROMPT="$(gp_add_virtualenv_to_prompt)$PROMPT_START$($prompt_callback)$STATUS_PREFIX$STATUS$PROMPT_END"
  else
    NEW_PROMPT="$EMPTY_PROMPT"
  fi
  
  # don't update the prompt, just return the git part of the prompt
  # Thus this script won't clobber my custom prompt but become part of it
  # muahahahahahahahahah ... 
  #PS1="${NEW_PROMPT//_LAST_COMMAND_INDICATOR_/${LAST_COMMAND_INDICATOR}${ResetColor}}"
  echo "$STATUS_PREFIX$STATUS"

  command rm "$GIT_INDEX_PRIVATE" 2>/dev/null
}

function printPrompt {
  echo "printPrompt called" >> /tmp/gitp.log
  local LAST_COMMAND_INDICATOR
  local PROMPT_LEADING_SPACE
  local PROMPT_START
  local PROMPT_END
  local EMPTY_PROMPT
  local Blue="\[\033[0;34m\]"

  git_prompt_config

  export __GIT_PROMPT_IGNORE_STASH=${GIT_PROMPT_IGNORE_STASH}
  export __GIT_PROMPT_SHOW_UPSTREAM=${GIT_PROMPT_SHOW_UPSTREAM}
  export __GIT_PROMPT_IGNORE_SUBMODULES=${GIT_PROMPT_IGNORE_SUBMODULES}

  if [ -z "${GIT_PROMPT_SHOW_UNTRACKED_FILES}" ]; then
    export __GIT_PROMPT_SHOW_UNTRACKED_FILES=all
  else
    export __GIT_PROMPT_SHOW_UNTRACKED_FILES=${GIT_PROMPT_SHOW_UNTRACKED_FILES}
  fi

  if [ -z "${GIT_PROMPT_SHOW_CHANGED_FILES_COUNT}" ]; then
    export __GIT_PROMPT_SHOW_CHANGED_FILES_COUNT=1
  else
    export __GIT_PROMPT_SHOW_CHANGED_FILES_COUNT=${GIT_PROMPT_SHOW_CHANGED_FILES_COUNT}
  fi

  local GIT_INDEX_PRIVATE="$(createPrivateIndex)"
  #important to define GIT_INDEX_FILE as local: This way it only affects this function (and below) - even with the export afterwards
  local GIT_INDEX_FILE
  export GIT_INDEX_FILE="$GIT_INDEX_PRIVATE"

  local -a git_status_fields
  #gsf=$git_status_fields
  git_status_fields=($("$__GIT_STATUS_CMD" 2>/dev/null))
  

  export GIT_BRANCH=$(replaceSymbols ${git_status_fields[0]})
  local GIT_REMOTE="$(replaceSymbols ${git_status_fields[1]})"
  if [[ "." == "$GIT_REMOTE" ]]; then
    unset GIT_REMOTE
  fi

  local GIT_UPSTREAM_PRIVATE="${git_status_fields[2]}"
  if [[ -z "${__GIT_PROMPT_SHOW_UPSTREAM}" || "^" == "$GIT_UPSTREAM_PRIVATE" ]]; then
    unset GIT_UPSTREAM
  else
    export GIT_UPSTREAM=${GIT_UPSTREAM_PRIVATE}
    local GIT_FORMATTED_UPSTREAM="${GIT_PROMPT_UPSTREAM//_UPSTREAM_/\$GIT_UPSTREAM}"
  fi

  local GIT_STAGED=${git_status_fields[3]}
  local GIT_CONFLICTS=${git_status_fields[4]}
  local GIT_CHANGED=${git_status_fields[5]}
  local GIT_UNTRACKED=${git_status_fields[6]}
  local GIT_STASHED=${git_status_fields[7]}
  local GIT_CLEAN=${git_status_fields[8]}

  local NEW_PROMPT="$EMPTY_PROMPT"
  if [[ -n "$git_status_fields" ]]; then

    case "$GIT_BRANCH" in
      $GIT_PROMPT_MASTER_BRANCHES)
        local STATUS_PREFIX="${PROMPT_LEADING_SPACE}${GIT_PROMPT_PREFIX}${GIT_PROMPT_MASTER_BRANCH}\${GIT_BRANCH}${ResetColor}${GIT_FORMATTED_UPSTREAM}"
        ;;
      *)
        local STATUS_PREFIX="${PROMPT_LEADING_SPACE}${GIT_PROMPT_PREFIX}${GIT_PROMPT_BRANCH}\${GIT_BRANCH}${ResetColor}${GIT_FORMATTED_UPSTREAM}"
        ;;
    esac
    local STATUS=""

    # __add_status KIND VALEXPR INSERT
    # eg: __add_status  'STAGED' '-ne 0'

    __chk_gitvar_status() {
      local v
      if [[ "x$2" == "x-n" ]] ; then
        v="$2 \"\$GIT_$1\""
      else
        v="\$GIT_$1 $2"
      fi
      if eval "test $v" ; then
        if [[ $# -lt 2 || "$3" != '-' ]] && [[ "x$__GIT_PROMPT_SHOW_CHANGED_FILES_COUNT" == "x1" || "x$1" == "xREMOTE" ]]; then
          __add_status "\$GIT_PROMPT_$1\$GIT_$1\$ResetColor"
        else
          __add_status "\$GIT_PROMPT_$1\$ResetColor"
        fi
      fi
    }
    
    __add_gitvar_status() {
      __add_status "\$GIT_PROMPT_$1\$GIT_$1\$ResetColor"
    }

    # __add_status SOMETEXT
    __add_status() {
      eval "STATUS=\"$STATUS$1\""
    }

    __chk_gitvar_status 'REMOTE'     '-n'
    if [[ $GIT_CLEAN -eq 0 ]] || [[ $GIT_PROMPT_CLEAN != "" ]]; then
      __add_status        "$GIT_PROMPT_SEPARATOR"
      __chk_gitvar_status 'STAGED'     '!= "0" -a $GIT_STAGED != "^"'
      __chk_gitvar_status 'CONFLICTS'  '!= "0"'
      __chk_gitvar_status 'CHANGED'    '!= "0"'
      __chk_gitvar_status 'UNTRACKED'  '!= "0"'
      __chk_gitvar_status 'STASHED'    '!= "0"'
      __chk_gitvar_status 'CLEAN'      '= "1"'   -
    fi
    __add_status        "$ResetColor$GIT_PROMPT_SUFFIX"

    NEW_PROMPT="$(gp_add_virtualenv_to_prompt)$PROMPT_START$($prompt_callback)$STATUS_PREFIX$STATUS$PROMPT_END"
  else
    NEW_PROMPT="$EMPTY_PROMPT"
  fi
  
  # don't update the prompt, just return the git part of the prompt
  # Thus this script won't clobber my custom prompt but become part of it
  # muahahahahahahahahah ... 
  #PS1="${NEW_PROMPT//_LAST_COMMAND_INDICATOR_/${LAST_COMMAND_INDICATOR}${ResetColor}}"
  echo "$STATUS_PREFIX$STATUS"

  command rm "$GIT_INDEX_PRIVATE" 2>/dev/null
}

# Helper function that returns virtual env information to be set in prompt
# Honors virtualenvs own setting VIRTUAL_ENV_DISABLE_PROMPT
function gp_add_virtualenv_to_prompt {
  echo "gp_add_virtualenv_to_prompt called" >> /tmp/gitp.log
  local ACCUMULATED_VENV_PROMPT=""
  local VENV=""
  if [[ -n "$VIRTUAL_ENV" && -z "${VIRTUAL_ENV_DISABLE_PROMPT-}" ]]; then
    VENV=$(basename "${VIRTUAL_ENV}")
    ACCUMULATED_VENV_PROMPT="${ACCUMULATED_VENV_PROMPT}${GIT_PROMPT_VIRTUALENV//_VIRTUALENV_/${VENV}}"
  fi
  if [[ -n "$NODE_VIRTUAL_ENV" && -z "${NODE_VIRTUAL_ENV_DISABLE_PROMPT-}" ]]; then
    VENV=$(basename "${NODE_VIRTUAL_ENV}")
    ACCUMULATED_VENV_PROMPT="${ACCUMULATED_VENV_PROMPT}${GIT_PROMPT_VIRTUALENV//_VIRTUALENV_/${VENV}}"
  fi
  if [[ -n "$CONDA_DEFAULT_ENV" ]]; then
    VENV=$(basename "${CONDA_DEFAULT_ENV}")
    ACCUMULATED_VENV_PROMPT="${ACCUMULATED_VENV_PROMPT}${GIT_PROMPT_VIRTUALENV//_VIRTUALENV_/${VENV}}"
  fi
  echo "$ACCUMULATED_VENV_PROMPT"
}

# Use exit status from declare command to determine whether input argument is a
# bash function
function is_function {
  echo "is_function called" >> /tmp/gitp.log
  declare -Ff "$1" >/dev/null;
}

# Helper function that truncates $PWD depending on window width
# Optionally specify maximum length as parameter (defaults to 1/3 of terminal)
function gp_truncate_pwd {
  echo "gp_truncate_pwd called" >> /tmp/gitp.log
  local tilde="~"
  local newPWD="${PWD/#${HOME}/${tilde}}"
  local pwdmaxlen=${1:-$((${COLUMNS:-80}/3))}
  [ ${#newPWD} -gt $pwdmaxlen ] && newPWD="...${newPWD:3-$pwdmaxlen}"
  echo -n "$newPWD"
}

# Sets the window title to the given argument string
function gp_set_window_title {
  echo "gp_set_window_title called" >> /tmp/gitp.log
  echo -ne "\[\033]0;"$@"\007\]"
}

function prompt_callback_default {
  echo "prompt_callback_default called" >> /tmp/gitp.log
  return
}

# toggle gitprompt
function git_prompt_toggle {
  echo "git_prompt_toggle called" >> /tmp/gitp.log
  if [[ "$GIT_PROMPT_DISABLE" = 1 ]]; then
    GIT_PROMPT_DISABLE=0
  else
    GIT_PROMPT_DISABLE=1
  fi
  return
}

function gp_install_prompt {
  echo "gp_install_prompt called" >> /tmp/gitp.log
  if [ -z "$OLD_GITPROMPT" ]; then
    OLD_GITPROMPT=$PS1
  fi

  if [ -z "$GIT_PROMPT_OLD_DIR_WAS_GIT" ]; then
    GIT_PROMPT_OLD_DIR_WAS_GIT=$(we_are_on_repo)
  fi

  if [ -z "$PROMPT_COMMAND" ]; then
    PROMPT_COMMAND=setGitPrompt
  else
    PROMPT_COMMAND=${PROMPT_COMMAND%% }; # remove trailing spaces
    PROMPT_COMMAND=${PROMPT_COMMAND%\;}; # remove trailing semi-colon

    local new_entry="setGitPrompt"
    case ";$PROMPT_COMMAND;" in
      *";$new_entry;"*)
        # echo "PROMPT_COMMAND already contains: $new_entry"
        :;;
      *)
        PROMPT_COMMAND="$PROMPT_COMMAND;$new_entry"
        # echo "PROMPT_COMMAND does not contain: $new_entry"
        ;;
    esac
  fi

  local setLastCommandStateEntry="setLastCommandState"
  case ";$PROMPT_COMMAND;" in
    *";$setLastCommandStateEntry;"*)
      # echo "PROMPT_COMMAND already contains: $setLastCommandStateEntry"
      :;;
    *)
      PROMPT_COMMAND="$setLastCommandStateEntry;$PROMPT_COMMAND"
      # echo "PROMPT_COMMAND does not contain: $setLastCommandStateEntry"
      ;;
  esac

  git_prompt_dir
  source "$__GIT_PROMPT_DIR/git-prompt-help.sh"
}

gp_install_prompt