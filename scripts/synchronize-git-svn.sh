#!/bin/bash

# IT IS VITALLY IMPORTANT THAT LINE ENDINGS ARE CONSISTENTLY SET IN THE
# MIRROR REPO -- AS IT DOES A MERGE AND MESSES THINGS UP OTHERWISE
#
# For a Windows-only project:
#
#  git config core.eol crlf
#  git config core.autocrlf false
#  git config core.safecrlf true
#  git config core.whitespace cr-at-eol
#
# Avoid problems with case-sensitive files:
#
#  git config core.ignorecase true

# TODO:
#
# function handle_error()
# {
#	if mail has not yet been sent
#		create guard for $1
#		echo "$1 failed, see $LOGFILE"
#	else if mail has been sent once for this error (i.e. guard exists)
#		update count for $1 guard to 2 or add marker
#		echo remainder and say that no more notices
# 		will be echoed until the guard has been removed
#	else don't echo anything
#
#	exit 1
# }

TRIGGERED_BY=${1:-NONE}

set -u

SCRIPT_FULL_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ----------------------
# --- CONFIGURATION ----
# ----------------------

# Configuration is sourced from scriptname.config

CONFIGFILE="${SCRIPT_FULL_PATH}.config"

if [[ ! -r "$CONFIGFILE" ]]
then
	echo "Config file $CONFIGFILE does not exist or is unreadable" >&2
	exit 1
fi

. $CONFIGFILE

# ----------------------
# --- IMPLEMENTATION ---
# ----------------------

function error_exit()
{
	local THECMD="$1"
	local LOGFILE="$2"

	echo "$THECMD FAILED" >> "$LOGFILE"
	echo "$THECMD failed, see $LOGFILE" >&2
	exit 1
}

function check_status()
{
	LAST_STATUS=$?

	local THECMD="$1"
	local LOGFILE="$2"

	echo "=>" >> "$LOGFILE"
	[[ $LAST_STATUS = 0 ]] || error_exit "$THECMD" "$LOGFILE"
	[[ $LAST_STATUS = 0 ]] && echo "$THECMD successful" >> "$LOGFILE"
	echo "----------------------------------------------" >> "$LOGFILE"
}

function check_failure()
{
	local THECMD="$1"
	local LOGFILE="$2"

	tail -6 "$LOGFILE" | grep 'error: git-svn died'
	[[ $? = 0 ]] && error_exit "$THECMD (probably wrong SVN credentials)" "$LOGFILE"
	tail -6 "$LOGFILE" | grep 'uthorization failed'
	[[ $? = 0 ]] && error_exit "$THECMD (probably wrong SVN credentials)" "$LOGFILE"
}

function rotate_logs()
{
	local LOGFILE="$1"

	if [[ -e "$LOGFILE" ]]; then
		for i in 3 2 1; do
			FROM="${LOGFILE}.${i}"
			TO="${LOGFILE}.$((i + 1))"
			[[ -e "$FROM" ]] && cp "$FROM" "$TO"
		done
		cp "$LOGFILE" "${LOGFILE}.1"
	fi

	> "$LOGFILE"
}

function release_lock()
{
	local LOCKDIR="$1"

	for toplevel_dir in /*; do
		if [[ "$LOCKDIR" = "$toplevel_dir" ]]; then
			echo "Refusing to rm -rf $LOCKDIR" >&2
			exit 1
		fi
	done

	rm -rf "$LOCKDIR"
}

function acquire_lock()
{
	# Inspired by http://wiki.bash-hackers.org/howto/mutex
	# and http://wiki.grzegorz.wierzowiecki.pl/code:mutex-in-bash

	local LOCKDIR="$1"
	local PIDFILE="${LOCKDIR}/pid"

	if mkdir "$LOCKDIR" &>/dev/null; then
		# lock succeeded

		# remove $LOCKDIR on exit
		trap 'release_lock "$LOCKDIR"' EXIT \
			|| { echo 'trap exit failed' >&2; exit 1; }

		# will trigger the EXIT trap above by `exit`
		trap 'echo "Sync script killed" >&2; exit 1' HUP INT QUIT TERM \
			|| { echo 'trap killsignals failed' >&2; exit 1; }

		echo "$$" >"$PIDFILE"

		return 0

	else
		# lock failed, now check if the other PID is alive
		OTHERPID="$(cat "$PIDFILE" 2>/dev/null)"

		if [[ $? != 0 ]]; then
			# PID file does not exists - propably direcotry
			# is being deleted
			return 1
		fi

		if ! kill -0 $OTHERPID &>/dev/null; then
			# lock is stale, remove it and restart
			echo "Stale lock in sync script" >&2
			release_lock "$LOCKDIR"
			acquire_lock "$LOCKDIR"
			return $?

		else
			# lock is valid and OTHERPID is active - exit,
			# we're locked!
			return 1
		fi
	fi
}

function wait_for_lock()
{
	local LOCKDIR="$1"

	# For timeout:
	#  - local WAIT_TIMEOUT=120
	#  - add `&& [[ $i -lt $WAIT_TIMEOUT ]]` to while condition
	#  - add ((i++)) into while body

	while ! acquire_lock "$LOCKDIR"; do
		sleep 1
	done
}

LAST_SVN_USER_FILE="${SCRIPT_FULL_PATH}.last_svn_user"

function set_subversion_user()
{
	local AUTHOR_EMAIL="$1"
	local SVN_URL="$2"
	local LOGFILE="$3"

	# cache last user to avoid unneccessary git-svn-auth-manager calls
	[[ -e "$LAST_SVN_USER_FILE" ]] \
		&& [[ "$(cat $LAST_SVN_USER_FILE)" == "$AUTHOR_EMAIL" ]] \
		&& return

	echo -n $AUTHOR_EMAIL > $LAST_SVN_USER_FILE
	check_status "echo -n $AUTHOR_EMAIL > $LAST_SVN_USER_FILE" "$LOGFILE"

	# reset SVN auth cache with git-svn-auth-manager
	if ! ~/bin/git-svn-auth-manager \
		-r "$AUTHOR_EMAIL" "$SVN_URL" &>> "$LOGFILE"
	then
		echo "PROBLEM WITH SVN OR WITH $AUTHOR_EMAIL SVN CREDENTIALS" >&2
		false
	fi
	check_status "~/bin/git-svn-auth-manager -r $AUTHOR_EMAIL $SVN_URL" "$LOGFILE"
}

function synchronize_svn_bridge_and_central_repo()
{
	local BRIDGE_REPO_PATH="$1"
	local LOGFILE="$2"

	pushd "$BRIDGE_REPO_PATH" > /dev/null
	check_status "pushd $BRIDGE_REPO_PATH" "$LOGFILE"

	# GIT_DIR (and possibly GIT_WORK_TREE) have to be unset,
	# otherwise the script will not work from post-update hook
	# see http://serverfault.com/questions/107608/git-post-receive-hook-with-git-pull-failed-to-find-a-valid-git-directory/107703#107703
	unset $(git rev-parse --local-env-vars)

	# get new SVN changes
	local AUTHORS_PROG="$HOME/bin/git-svn-auth-manager"
	git svn --authors-prog="$AUTHORS_PROG" fetch &>> "$LOGFILE"
	check_status "git svn --authors-prog=$AUTHORS_PROG fetch" "$LOGFILE"
	check_failure "git svn --authors-prog=$AUTHORS_PROG fetch" "$LOGFILE"

	# get new git changes
	git checkout master &>> "$LOGFILE"
	check_status "git checkout master" "$LOGFILE"
	git pull --rebase git-central-repo master &>> "$LOGFILE"
	check_status "git pull --rebase git-central-repo master" "$LOGFILE"

	# store the SVN URL and author of the last commit for `git svn dcommit`
	local SVN_URL=`git svn info --url`
	check_status "git svn info --url" "$LOGFILE"
	local AUTHOR_EMAIL=`git log -n 1 --format='%ae'`
	check_status "git log -n 1 --format='%ae'" "$LOGFILE"
	echo "Using SVN URL '$SVN_URL' and author email '$AUTHOR_EMAIL'" >> "$LOGFILE"

	# checkout detached head
	git checkout svn/git-svn &>> "$LOGFILE"
	check_status "git checkout svn/git-svn" "$LOGFILE"

	# create a merged log message for the merge commit to SVN
	# => note that we squash log messages together for merge commits
	# => experiment with the fomat, e.g. '%ai | [%an] %s' etc
	local MESSAGE=`git log --pretty=format:'%ai | %B [%an]' HEAD..master`
	check_status "git log --pretty=format:'%ai | %B [%an]' HEAD..master" "$LOGFILE"

	# merge changes from master to the SVN-tracking branch and commit to SVN
	# => note that we always record the merge with --no-ff
	git merge --no-ff --no-log -m "$MESSAGE" master &>> $LOGFILE
	check_status 'git merge --no-ff --no-log -m $MESSAGE master' $LOGFILE

	# set the SVN user and commit changes to SVN
	set_subversion_user "$AUTHOR_EMAIL" "$SVN_URL" "$LOGFILE"
	git svn --authors-prog="$AUTHORS_PROG" dcommit &>> "$LOGFILE"
	check_status "git svn --authors-prog=$AUTHORS_PROG dcommit" "$LOGFILE"

	# merge changes from the SVN-tracking branch back to master
	git checkout master &>> "$LOGFILE"
	check_status "git checkout master" "$LOGFILE"
	git merge svn/git-svn &>> "$LOGFILE"
	check_status "git merge svn/git-svn" "$LOGFILE"

	# fetch changes to central repo master from SVN bridge master
	# (note that cannot just `git push git-central-repo master`
	# as that would trigger the central repo update hook and deadlock)
	local CENTRAL_REPO_PATH="`git remote -v show | awk 'NR > 1 { exit }; { print $2 };'`"
	pushd "$CENTRAL_REPO_PATH" >/dev/null
	check_status "pushd $CENTRAL_REPO_PATH" "$LOGFILE"
	git fetch svn-bridge master:master &>> "$LOGFILE"
	check_status "git fetch svn-bridge master:master" "$LOGFILE"
	popd >/dev/null

	popd >/dev/null
}

LOGFILE="${SCRIPT_FULL_PATH}.log"
LOCKDIR="${SCRIPT_FULL_PATH}.lock"

wait_for_lock "$LOCKDIR"

rotate_logs "$LOGFILE"

if [[ "$TRIGGERED_BY" != "NONE" ]]
then
	echo "..................................................." >> "$LOGFILE"
	echo "Triggered by $TRIGGERED_BY" >> "$LOGFILE"
	echo "..................................................." >> "$LOGFILE"
fi

for repo in ${REPOS[@]}
do
	echo -e "______________________________________________\n" >> "$LOGFILE"

	if [[ -d "$repo" && -d "$repo/.git" ]] && \
		grep -qFx '[svn-remote "svn"]' "$repo/.git/config"
	then
		echo "Synchronizing repo '$repo'" >> "$LOGFILE"
		echo "Start: `date`" >> "$LOGFILE"
		echo -e "......................................\n" >> "$LOGFILE"

		synchronize_svn_bridge_and_central_repo "$repo" "$LOGFILE"

		echo "End: `date`" >> "$LOGFILE"

	else
		echo "Repo '$repo' does not exist or is not a git-svn repo" >&2
		echo "Repo '$repo' does not exist or is not a git-svn repo" >> "$LOGFILE"
	fi

	echo -e "______________________________________________\n" >> "$LOGFILE"

done
