#!/bin/bash

# sudo su git

set -u
set -x
set -e

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

cd "$BASEDIR"

CENTRAL_REPO="${BASEDIR}/central-repo-${BRANCHNAME}.git"
BRIDGE_REPO="${BASEDIR}/git-svn-bridge-${BRANCHNAME}.git"

# central repo

git init --bare "$CENTRAL_REPO"

pushd "$CENTRAL_REPO"

git remote add svn-bridge "$BRIDGE_REPO"

popd

# git-SVN bridge

git svn --prefix=svn/ init "$SVN_REPO_URL" "$BRIDGE_REPO"

pushd "$BRIDGE_REPO"

git svn --authors-prog="$GIT_SVN_AUTH_MANAGER" --log-window-size 10000 fetch
git remote add git-central-repo "$CENTRAL_REPO"
git push --all git-central-repo

popd

# central repo hooks

pushd "$CENTRAL_REPO"

cat > hooks/update << 'EOT'
#!/bin/bash
set -u
refname=$1
shaold=$2
shanew=$3

# we are only interested in commits to master
[[ "$refname" = "refs/heads/master" ]] || exit 0

# don't allow non-fast-forward commits
if [[ $(git merge-base "$shanew" "$shaold") != "$shaold" ]]; then
    echo "Non-fast-forward commits to master are not allowed"
    exit 1
fi
EOT

cat > hooks/post-update << EOT
#!/bin/bash

# trigger synchronization only on commit to master
for arg in "\$@"; do
    if [[ "\$arg" = "refs/heads/master" ]]; then
	$SYNCHRONIZE_SCRIPT GIT_HOOK
        exit \$?
    fi
done
EOT

chmod 755 hooks/{update,post-update}

./hooks/post-update refs/heads/master

popd
