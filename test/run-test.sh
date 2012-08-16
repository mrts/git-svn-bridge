#!/bin/bash

# See ../README.md for explanations
#
# Please run this script with a test user account.
#
# NOTE THAT THE SCRIPT CHANGES SVN CONFIGURATION AS FOLLOWS:
#
#  'store-plaintext-passwords = yes'
#
# IN ~/.subversion/servers
#
# AND GIT CONFIGURATION AS FOLLOWS:
#
#  git config --global user.name "Git-SVN Bridge (GIT SIDE)"
#  git config --global user.email "git-svn-bridge@company.com"

set -u

# For easy changing from command line:
#
# sed -i 's/GMAIL_SMTP_USERNAME="username@gmail.com/GMAIL_SMTP_USERNAME="YOURUSERNAME@gmail.com/;s/GMAIL_SMTP_PASSWORD="userpassword/GMAIL_SMTP_PASSWORD="YOURUSERPASSWORD/' run-test.sh
#
GMAIL_SMTP_USERNAME="username@gmail.com"
GMAIL_SMTP_PASSWORD="userpassword"

function die()
{
	local THE_VARIABLE="$1"
	echo "Please change $THE_VARIABLE before running $0"
	exit 1
}

[[ "$GMAIL_SMTP_USERNAME" == "username@gmail.com" ]] \
	&& die "GMAIL_SMTP_USERNAME"
[[ "$GMAIL_SMTP_PASSWORD" == "userpassword" ]] \
	&& die "GMAIL_SMTP_PASSWORD"

# assure that .subversion is created
svn info /tmp

set -e
set -x

mkdir {bin,git,svn,test}

# svn

STORE_PASSWD='store-plaintext-passwords = yes'
grep -qx "$STORE_PASSWD" ~/.subversion/servers \
	|| echo "$STORE_PASSWD" >> ~/.subversion/servers

cd ~/svn
svnadmin create svn-repo
svn co file://`pwd`/svn-repo svn-checkout

cd svn-checkout
mkdir -p trunk/src
echo 'int main() { return 0; }' > trunk/src/main.cpp
svn add trunk
svn ci -m "First commit."

# svnserve

SVNSERVE_PIDFILE="$HOME/svn/svnserve.pid"
SVNSERVE_LOGFILE="$HOME/svn/svnserve.log"
SVNSERVE_CONFFILE="$HOME/svn/svnserve.conf"
SVNSERVE_USERSFILE="$HOME/svn/svnserve.users"

>> $SVNSERVE_LOGFILE

cat > "$SVNSERVE_CONFFILE" << EOT
[general]
realm = git-SVN test
anon-access = none
password-db = $SVNSERVE_USERSFILE
EOT

cat > "$SVNSERVE_USERSFILE" << EOT
[users]
git-svn-bridge = git-svn-bridge
alice = alice
bob = bob
carol = carol
dave = dave
EOT

TAB="`printf '\t'`"

cat > ~/svn/Makefile << EOT
svnserve-start:
${TAB}svnserve -d \\
${TAB}${TAB}--pid-file "$SVNSERVE_PIDFILE" \\
${TAB}${TAB}--log-file "$SVNSERVE_LOGFILE" \\
${TAB}${TAB}--config-file "$SVNSERVE_CONFFILE" \\
${TAB}${TAB}-r ~/svn/svn-repo

svnserve-stop:
${TAB}kill \`cat "$SVNSERVE_PIDFILE"\`
EOT

make -f ~/svn/Makefile svnserve-start

# git

git config --global user.name "Git-SVN Bridge (GIT SIDE)"
git config --global user.email "git-svn-bridge@company.com"

cd ~/git
git init --bare git-central-repo-trunk.git
cd git-central-repo-trunk.git
git remote add svn-bridge ../git-svn-bridge-trunk

SVN_REPO_URL="svn://localhost/trunk"
cd ~/git
git svn init --prefix=svn/ $SVN_REPO_URL git-svn-bridge-trunk
cd git-svn-bridge-trunk
AUTHORS='/tmp/git-svn-bridge-authors'
echo 'git-svn-bridge = Git SVN Bridge <git-svn-bridge@company.com>' > $AUTHORS
echo -e "\n>>> USE 'git-svn-bridge' AS PASSWORD <<<\n"
git svn fetch --authors-file="$AUTHORS" --log-window-size 10000

git branch -a -v

git remote add git-central-repo ../git-central-repo-trunk.git
git push --all git-central-repo

cd ~/git
git clone git-central-repo-trunk.git git-central-repo-clone
cd git-central-repo-clone
git log

cd ~/git/git-central-repo-trunk.git
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

cat > hooks/post-update << 'EOT'
#!/bin/bash

# trigger synchronization only on commit to master
for arg in "$@"; do
    if [[ "$arg" = "refs/heads/master" ]]; then
        /home/git-svn-bridge/bin/synchronize-git-svn.sh GIT_HOOK
        exit $?
    fi
done
EOT

cat > ~/bin/synchronize-git-svn.sh << 'EOT'
# test script to verify that the git hook works properly
echo "Commit from $1 to master" > /tmp/test-synchronize-git-svn
exit 1 # test that error exit does not abort the update
EOT

chmod 755 hooks/update
chmod 755 hooks/post-update
chmod 755 ~/bin/synchronize-git-svn.sh

cd ~/git/git-central-repo-clone
echo "void do_nothing() { }" >> src/main.cpp
git commit -am "Update main.cpp"
git push
less /tmp/test-synchronize-git-svn

echo "void do_nothing() { }" >> src/main.cpp
git add src/
git commit --amend
set +e
git push --force
set -e
git reset --hard origin/master

cd ~/git
git clone --recursive git://github.com/mrts/git-svn-bridge.git github-git-svn-bridge-utils
cd github-git-svn-bridge-utils/git-svn-auth-manager
ENCRYPTION_KEY=`tr -dc '[:alnum:]' < /dev/urandom | head -c 16`
sed -i "s/CHANGETHIS/$ENCRYPTION_KEY/" src/EncryptedUserRepository.cs
read -p 'Should I remove the database? (y/n) ' SHOULD_REMOVE_DB
[[ "$SHOULD_REMOVE_DB" = "y" ]] && make mrproper
make install_config
GITSVNAUTHMGRCONF="$HOME/.config/git-svn-auth-manager/config"
sed -i "s/username@gmail.com/$GMAIL_SMTP_USERNAME/" "$GITSVNAUTHMGRCONF"
sed -i "s/userpassword/$GMAIL_SMTP_PASSWORD/" "$GITSVNAUTHMGRCONF"
set +x
BRIDGE_EMAIL="git-svn-bridge@company.com"
echo -e "\n>>> USE 'git-svn-bridge' AS PASSWORD AND '$BRIDGE_EMAIL' AS EMAIL <<<\n"
set -x
~/bin/git-svn-auth-manager -a git-svn-bridge
~/bin/git-svn-auth-manager -r $BRIDGE_EMAIL $SVN_REPO_URL
set +e
echo .dump | sqlite3 ~/.config/git-svn-auth-manager/userinfo.db
~/bin/git-svn-auth-manager -r $BRIDGE_EMAIL /tmp
set -e

cd ~/bin
cp ../git/github-git-svn-bridge-utils/scripts/synchronize-git-svn.sh .
cp ../git/github-git-svn-bridge-utils/scripts/synchronize-git-svn.sh.config .
./synchronize-git-svn.sh

cd ~/git/git-central-repo-clone
git pull --rebase
echo "void more_do_nothing() { }" >> src/main.cpp
git commit -am "Add more_do_nothing() to main.cpp"
git push

# Actors

cd ~/test
mkdir {alice,bob,carol,dave}

for name in alice bob; do
    set +x
    echo -e "\n>>> USE '$name' AS PASSWORD AND '$name@company.com' AS EMAIL <<<\n"
    set -x
    ~/bin/git-svn-auth-manager -a $name
    pushd $name
    svn --username $name --password $name co $SVN_REPO_URL
    popd
done

for name in carol dave; do
    set +x
    echo -e "\n>>> USE '$name' AS PASSWORD AND '$name@company.com' AS EMAIL <<<\n"
    set -x
    ~/bin/git-svn-auth-manager -a $name
    pushd $name
    git clone ~/git/git-central-repo-trunk.git git-trunk
    cd git-trunk
    git config user.name `~/bin/git-svn-auth-manager $name | sed 's/ <.*//'`
    git config user.email `~/bin/git-svn-auth-manager $name | sed 's/.*<\(.*\)>/\1/'`
    popd
done

make -f ~/svn/Makefile svnserve-stop

cat > alice.sh << 'EOT'
#!/bin/bash
pushd alice/trunk
echo 'void alice() { }' >> src/alice.cpp
svn --username alice --password alice up
svn add src/alice.cpp
svn --username alice --password alice ci -m "Protect the global cache with a mutex"
popd
EOT

cat > bob.sh << 'EOT'
#!/bin/bash
pushd bob/trunk
echo 'void bob() { }' >> src/bob.cpp
svn --username bob --password bob up
svn add src/bob.cpp
svn --username bob --password bob ci -m "Cache rendered templates"
echo 'void bob2() { }' >> src/bob.cpp
svn --username bob --password bob up
svn --username bob --password bob ci -m "Add tags to articles"
popd
EOT

cat > carol.sh << 'EOT'
#!/bin/bash
pushd carol/git-trunk
echo 'void carol1() { }' >> src/carol.cpp
git add src/carol.cpp
git commit -m "Add template tag library"
echo 'void carol2() { }' >> src/carol.cpp
git commit -am "Use template tag library for localized date format"
git pull --rebase
git push
echo 'void carol3() { }' >> src/carol.cpp
git commit -am "Use template filters to represent amounts in localized format"
git pull --rebase
git push
popd
EOT

cat > dave.sh << 'EOT'
#!/bin/bash
# dave is working on a task branch
pushd dave/git-trunk
git checkout -b payment-support
echo 'void dave1() { }' >> src/dave.cpp
git add src/dave.cpp
git commit -m "Add payment processing interface"
echo 'void dave2() { }' >> src/dave.cpp
git commit -am "Implement PayPal payments"
echo 'void dave3() { }' >> src/dave.cpp
git commit -am "Implement credit card payments"
git fetch
git rebase origin/master
echo 'void dave4() { }' >> src/dave.cpp
git commit -am "Add storage encryption for payments"
git checkout master
git pull --rebase
git merge --no-ff payment-support
git push
popd
EOT

cat > cron.sh << 'EOT'
#!/bin/bash
~/bin/synchronize-git-svn.sh CRON
EOT

chmod 755 *.sh

cat > Makefile << EOT
all: alice bob carol dave cron
.PHONY: all alice bob carol dave cron svn

EOT

for name in alice bob carol dave cron; do
    echo -e "${name}:\n\t./${name}.sh\n" >> Makefile
done

set +x

echo
echo '----------------------------------------'
echo 'STAGE IS SET, RUN'
echo '   cd test'
echo '   make -f ~/svn/Makefile svnserve-start'
echo '   make'
echo '   make -f ~/svn/Makefile svnserve-stop'
echo '----------------------------------------'
echo
