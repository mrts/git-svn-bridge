*git*-*Subversion* bridge
=========================

It should be quite obvious to GitHub users why our team likes *git* - we
branch, diff, merge and rebase heavily, work offline, stash, amend commits and
do other *git*-specific things that make *git* so fun and useful.

However, our corporate standard is *Subversion*. It is simple and
reliable, the history is immutable and the central repository lives in the
secure datacenter. Project managers and salespeople can use *TortoiseSVN* to
access the project repository as well, keeping project documents neatly
organized alongside source repositories; administrators have easy tools for
managing authorization and authentication etc. Everyone is generally happy with
it.

To reap the best of both worlds, we have setup a *git*-*Subversion*
bridge that synchronizes changes between our team *git* repository and
the corporate *Subversion* repository. The obvious requirement is that
our *git* usage has to be transparent to other *Subversion* users, not
interfere with their work or damage the corporate repository.

The setup looks like this:

![image](https://raw.github.com/mrts/git-svn-bridge/master/doc/git-Subversion_bridge.png)

We have used this setup in production for more than a year (albeit in a
somewhat simpler incarnation), so we have sorted out most of the problem points
and are content with it. It may also work for you in a similar situation.

This document gives an overview of the setup.

If you have administrator access to the *Subversion* repository (we
don't), be sure to check out [SubGit](http://subgit.com/). It may or may
not make the setup simpler.

Overview and caveats
--------------------

-   Each update of *master* in the central *git* repository will trigger
    synchronization with *Subversion*. Additionally, there is a *cron* job that
    runs the synchronization every *n* minutes (so that the repository is
    updated even if there are no commits at *git* side). Concurrent
    synchronization is properly guarded with a lock in the bundled
    synchronization script.

-   There is no exchange of branches between *git* and *Subversion*. The
    *git* side tracks the trunk or any other main *Subversion* branch.
    Branching happens at *git* side with short-lived task branches that
    need not to be shared with *Subversion* users. Separate *git*
    repositories are used for tracking other long-lived *Subversion*
    branches.

-   As *Subversion* history is linear, *git* merge commits will be squashed
    into a single commit (see examples below). For us this is no problem as,
    in the spirit of continuous integration, we consider the task branches to
    be lightweight, ephemeral "units of work" that can go to mainline in a
    single chunk and as the branch history is retained in *git*.

-   To properly set author information in commits between *git* and
    *Subversion*, *Subversion* user passwords need to be available to
    the synchronization script. A fairly secure program,
    `git-svn-auth-manager`, that keeps passwords in an encrypted
    *SQLite* database is bundled and the synchronization script uses
    that by default (see description below).

-   *git* history is duplicated as commits first go up to and then come
    back down again with a `git-svn-id` from *Subversion*. Although this
    may sound confusing it has not been a big problem in practice (see
    examples below; note that `--no-ff` is used to record the merges).
    *Subversion* history remains clean.

-   Rewriting history on *master* will probably mess up the
    *git*-*Subversion* synchronization so it is disabled with the update
    hook in the central *git* repository (we haven't tried though, this
    just seems a sane precaution).

-   If the project is Windows-only then the *git* bridge repo must be
    configured to retain Windows line endings. (*TODO: describe how.*)

### Subversion's view on history

Squashed branch merge commit to *master* from *git* (see `dave.sh` below):

    $ svn log trunk@r9 -l 1
    ------------------------------------------------------------------------
    r9 | dave | 2012-08-26 13:22:39 +0300 (Sun, 26 Aug 2012) | 10 lines
    
    2012-08-26 13:22:36 +0300 | Merge branch 'payment-support'
     [Dave]
    2012-08-26 13:22:36 +0300 | Add storage encryption for payments
     [Dave]
    2012-08-26 13:22:36 +0300 | Implement credit card payments
     [Dave]
    2012-08-26 13:22:36 +0300 | Implement PayPal payments
     [Dave]
    2012-08-26 13:22:36 +0300 | Add payment processing interface
     [Dave]
    ------------------------------------------------------------------------

Single commit to *master* from *git* (see `carol.sh` below):

    $ svn log trunk@r8 -l 1
    ------------------------------------------------------------------------
    r8 | carol | 2012-08-26 13:22:36 +0300 (Sun, 26 Aug 2012) | 2 lines
    
    2012-08-26 13:22:35 +0300 | Use template filters to represent amounts in localized format
     [Carol]
    ------------------------------------------------------------------------

### Git's view on history

Single commit before synchronization:

    $ git log a165c -1
    commit a165c9857eebb168e44b22278950cd930259394c
    Author: Carol <carol@company.com>
    Date:   Sun Aug 26 13:22:35 2012 +0300
    
        Use template filters to represent amounts in localized format

After synchronization, it will be duplicated with another commit that has come
down from *Subversion*:

    $ git log
    ...
    commit 10fb01c123851b02f2105c98cb7c9adc47a1bb39
    Merge: fc656d9 a165c98
    Author: Carol <carol@company.com>
    Date:   Sun Aug 26 13:22:36 2012 +0300
    
        2012-08-26 13:22:35 +0300 | Use template filters to represent amounts in localized format
         [Carol]
        
        git-svn-id: svn://localhost/trunk@8 49763079-ba47-4a7b-95a0-4af80b88d9d8
    ...
    commit a165c9857eebb168e44b22278950cd930259394c
    Author: Carol <carol@company.com>
    Date:   Sun Aug 26 13:22:35 2012 +0300
    
        Use template filters to represent amounts in localized format
    ...

For each branch merge, an additional squashed merge commit will come down from
*Subversion* as shown in the previous section.

Setup
-----

The following walkthrough is provided both for documentation and for
hands-on testing. All of this can be run in one go with the [test
script](http://github.com/mrts/git-svn-bridge/blob/master/test/run-test.sh).
After you have prepared the envrionment, new bridge repositories for other
*Subversion* branches can be set up with the [branch setup script](http://github.com/mrts/git-svn-bridge/blob/master/scripts/setup-svn-branch-git-bridge.sh).

Start by creating the bridge user (*use your actual email address instead of
YOUREMAIL@gmail.com, it is used later during setup and testing*):

    $ sudo adduser git-svn-bridge
    $ sudo su git-svn-bridge
    $ set -u
    $ YOUR_EMAIL=YOUREMAIL@gmail.com
    $ git config --global user.name "Git-SVN Bridge (GIT SIDE)"
    $ git config --global user.email "$YOUR_EMAIL"
    $ cd
    $ mkdir {bin,git,svn,test}

### Subversion

Assure that *Subversion* caches passwords (*only last git-svn-auth-manager
reset user password will be cached; let me know if this does not meet your
security requirements, there are ways around this*):

    $ echo 'store-plaintext-passwords = yes' >> ~/.subversion/servers

Create the *Subversion* repository (*in real life you would simply use the
existing central Subversion repository*):

    $ cd ~/svn
    $ svnadmin create svn-repo
    $ svn co file://`pwd`/svn-repo svn-checkout
    Checked out revision 0.

Commit a test revision to *Subversion*:

    $ cd svn-checkout
    $ mkdir -p trunk/src
    $ echo 'int main() { return 0; }' > trunk/src/main.cpp
    $ svn add trunk
    A         trunk
    A         trunk/src
    A         trunk/src/main.cpp
    $ svn ci -m "First commit."
    Adding         trunk
    Adding         trunk/src
    Adding         trunk/src/main.cpp
    Transmitting file data .
    Committed revision 1.

Setup `svnserve` to serve the repository:

    $ cd ~/svn

    $ SVNSERVE_PIDFILE="$HOME/svn/svnserve.pid"
    $ SVNSERVE_LOGFILE="$HOME/svn/svnserve.log"
    $ SVNSERVE_CONFFILE="$HOME/svn/svnserve.conf"
    $ SVNSERVE_USERSFILE="$HOME/svn/svnserve.users"
    
    $ >> $SVNSERVE_LOGFILE
    
    $ cat > "$SVNSERVE_CONFFILE" << EOT
    [general]
    realm = git-SVN test
    anon-access = none
    password-db = $SVNSERVE_USERSFILE
    EOT
    
    $ cat > "$SVNSERVE_USERSFILE" << EOT
    [users]
    git-svn-bridge = git-svn-bridge
    alice = alice
    bob = bob
    carol = carol
    dave = dave
    EOT
    
    $ TAB="`printf '\t'`"
    
    $ cat > ~/svn/Makefile << EOT
    svnserve-start:
    ${TAB}svnserve -d \\
    ${TAB}${TAB}--pid-file "$SVNSERVE_PIDFILE" \\
    ${TAB}${TAB}--log-file "$SVNSERVE_LOGFILE" \\
    ${TAB}${TAB}--config-file "$SVNSERVE_CONFFILE" \\
    ${TAB}${TAB}-r ~/svn/svn-repo
    
    svnserve-stop:
    ${TAB}kill \`cat "$SVNSERVE_PIDFILE"\`
    EOT

Start `svnserve`:

    $ make svnserve-start

### Git

Setup the central repository that *git* users will use:

    $ cd ~/git
    $ git init --bare git-central-repo-trunk.git
    Initialized empty Git repository in /home/git-svn-bridge/git/git-central-repo-trunk.git/
    $ cd git-central-repo-trunk.git
    $ git remote add svn-bridge ../git-svn-bridge-trunk

Setup the *git*-*Subversion* bridge repository:

    $ cd ~/git
    $ SVN_REPO_URL="svn://localhost/trunk"
    $ git svn init --prefix=svn/ $SVN_REPO_URL git-svn-bridge-trunk
    Initialized empty Git repository in /home/git-svn-bridge/git/git-svn-bridge-trunk/.git/

Fetch changes from *Subversion*:

    $ cd git-svn-bridge-trunk
    $ AUTHORS='/tmp/git-svn-bridge-authors'
    $ echo "git-svn-bridge = Git SVN Bridge <${YOUR_EMAIL}>" > $AUTHORS
    $ git svn fetch --authors-file="$AUTHORS" --log-window-size 10000
    Authentication realm: <svn://localhost:3690> git-SVN test
    Password for 'git-svn-bridge': git-svn-bridge
       A   src/main.cpp
    r1 = 061725282bdccf7f4a8efa66ee34b195ca7070fc (refs/remotes/svn/git-svn)
    Checked out HEAD:
      file:///home/git-svn-bridge/svn/svn-repo/trunk r1

Verify that the result is OK:

    $ git branch -a -v
    * master              0617252 First commit.
      remotes/svn/git-svn 0617252 First commit.

Add the central repository as a remote to the bridge repository and push
changes from *Subversion* to the central repository:

    $ git remote add git-central-repo ../git-central-repo-trunk.git
    $ git push --all git-central-repo
    Counting objects: 4, done.
    Writing objects: 100% (4/4), 332 bytes, done.
    Total 4 (delta 0), reused 0 (delta 0)
    Unpacking objects: 100% (4/4), done.
    To ../git-central-repo-trunk.git
     * [new branch]      master -> master

Clone the central repository and verify that the *Subversion* test
commit is there:

    $ cd ~/git
    $ git clone git-central-repo-trunk.git git-central-repo-clone
    Cloning into 'git-central-repo-clone'...
    done.

    $ cd git-central-repo-clone
    $ git log
    commit 061725282bdccf7f4a8efa66ee34b195ca7070fc
    Author: git-svn-bridge <git-svn-bridge>
    Date:   Wed Aug 15 11:38:57 2012 +0000

       First commit.

       git-svn-id: file:///home/git-svn-bridge/svn/svn-repo/trunk@1 b4f7b086-5416-...

Create the *git* hook that blocks non-fast-forward commits in the
central repository:

    $ cd ~/git/git-central-repo-trunk.git
    $ cat > hooks/update << 'EOT'
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

    $ chmod 755 hooks/update

Create the *git* hook that triggers synchronization:

    $ cat > hooks/post-update << 'EOT'
    #!/bin/bash

    # trigger synchronization only on commit to master
    for arg in "$@"; do
        if [[ "$arg" = "refs/heads/master" ]]; then
            /home/git-svn-bridge/bin/synchronize-git-svn.sh GIT_HOOK
            exit $?
        fi
    done
    EOT

    $ chmod 755 hooks/post-update

    $ cat > ~/bin/synchronize-git-svn.sh << 'EOT'
    # test script to verify that the git hook works properly
    echo "Commit from $1 to master" > /tmp/test-synchronize-git-svn
    exit 1 # test that error exit does not abort the update
    EOT

    $ chmod 755 ~/bin/synchronize-git-svn.sh

Test that the hook works:

    $ cd ~/git/git-central-repo-clone
    $ echo "void do_nothing() { }" >> src/main.cpp

    $ git commit -am "Update main.cpp"
    [master 2c833e2] Update main.cpp
     1 file changed, 1 insertion(+)

    $ git push
    Counting objects: 7, done.
    Writing objects: 100% (4/4), 341 bytes, done.
    Total 4 (delta 0), reused 0 (delta 0)
    Unpacking objects: 100% (4/4), done.
    To /home/git-svn-bridge/git/git-central-repo-trunk.git
       5b73892..2c833e2  master -> master

    $ cat /tmp/test-synchronize-git-svn
    Commit from GIT_HOOK to master

Verify that non-fast-forward commits to *master* are not allowed:

    $ echo "void do_nothing() { }" >> src/main.cpp
    $ git add src/
    $ git commit --amend
    [master d2f9a16] Update main.cpp
     1 file changed, 2 insertions(+)

    $ git push --force
    Counting objects: 7, done.
    Compressing objects: 100% (2/2), done.
    Writing objects: 100% (4/4), 345 bytes, done.
    Total 4 (delta 0), reused 0 (delta 0)
    Unpacking objects: 100% (4/4), done.
    remote: Non-fast-forward commits to master are not allowed
    remote: error: hook declined to update refs/heads/master
    To /home/git-svn-bridge/git/git-central-repo-trunk.git
     ! [remote rejected] master -> master (hook declined)
    error: failed to push some refs to '/home/git-svn-bridge/git/git-central-repo-trunk.git'

    $ git reset --hard origin/master

So far, so good. Let's wire in the real synchronization utilities now.

### Synchronization utilities

Real synchronization relies on

-   the [synchronization
    script](https://github.com/mrts/git-svn-bridge/blob/master/scripts/synchronize-git-svn.sh)
    that controls the actual synchronization

-   `git-svn-auth-manager`, a utility that manages *Subversion*
    authentication and commit author mapping between *git* and
    *Subversion* (**note that this is the sweet spot of the solution**);
    it is described in more detail in a [separate
    README](https://github.com/mrts/git-svn-bridge/blob/master/git-svn-auth-manager/README.rst).

Start by cloning this repository:

    $ cd ~/git
    $ git clone --recursive git://github.com/mrts/git-svn-bridge.git github-git-svn-bridge-utils

|**Warning to Ubuntu 16.04 users**|
|---------------------------------|
|The versions of *Mono* and *Git* provided in Ubuntu 16.04 cause problems as described below, please use [latest *Mono*](http://www.mono-project.com/docs/getting-started/install/linux/#debian-ubuntu-and-derivatives) and [*Git*](https://launchpad.net/~git-core/+archive/ubuntu/ppa) if you run into problems.|

#### git-svn-auth-manager

Install required libraries and tools:

    $ sudo apt-get install build-essential mono-devel libssl-dev tcl

Change the encryption key:

    $ cd github-git-svn-bridge-utils/git-svn-auth-manager
    $ ENCRYPTION_KEY=`tr -dc '[:alnum:]' < /dev/urandom | head -c 16`
    $ sed -i "s/CHANGETHIS/$ENCRYPTION_KEY/" src/EncryptedUserRepository.cs
    $ git diff src
    ...
    -               private const string ENCRYPTION_KEY = "CHANGETHIS";
    +               private const string ENCRYPTION_KEY = "TNwwmT2Wc3xVTole";
    ...

This is generally not necessary, but if you have an old database lying
around from previous runs, it should be removed now as the encryption
key has changed (**careful with your actual user information**):

    $ make mrproper
    ...
    rm -f ~/.config/git-svn-auth-manager/userinfo.db
    ...

Build and install `git-svn-auth-manager`:

    $ make install
    ...
    install -m 711 -D bin/git-svn-auth-manager ~/bin/git-svn-auth-manager

Verify that it works:

    $ ~/bin/git-svn-auth-manager
    git-svn-auth-manager: too few, too many or invalid arguments

    Helper utility for running a git-SVN bridge.
    Manages SVN authentication for git and user mapping between git and SVN.

    Usage:
        either with a single non-option argument to output user
        name and email suitable for `git --authors-prog`:

            git-svn-auth-manager SVN_USERNAME

        or with a single option to add users or change passwords:

            git-svn-auth-manager OPTION=SVN_USERNAME

        or with a single option and single non-option argument to reset
        SVN authentication cache:

            git-svn-auth-manager --reset-auth-for=EMAIL SVN_URL

    Options:
          --help, -h             Show help
          --add-user, -a=VALUE   Add user information to the database
          --change-passwd-for, -p=VALUE
                                 Change user's password in the database
          --reset-auth-for, -r=VALUE
                                 Reset SVN auth cache with user's credentials;
                                   option argument is user's email; SVN URL
                                   required as non-option argument

|**Note**|
|--------|
|If `~/bin/git-svn-auth-manager` crashes, then this is caused by *Mono* problems, please update *Mono* as described above|

Secure the key - as encryption key is embedded in
`git-svn-auth-manager`, it needs to be owned by root and be made
execute-only (`make install` *took care of the execute-only part already,
but let's be extra safe and explicit here*):

    $ sudo chown root: ~/bin/git-svn-auth-manager
    $ sudo chmod 711 ~/bin/git-svn-auth-manager
    $ ls -l ~/bin/git-svn-auth-manager
    -rwx--x--x 1 root root 697208 Aug 23 17:38 git-svn-auth-manager

Add the *git-svn-bridge* user for testing (*as before, use your actual email
address instead of YOUREMAIL@gmail.com and 'git-svn-bridge' as password*):

    $ ~/bin/git-svn-auth-manager -a git-svn-bridge
    Adding/overwriting SVN user git-svn-bridge
    SVN password: git-svn-bridge
    SVN password (confirm): git-svn-bridge
    Email: YOUREMAIL@gmail.com
    Name: Git-SVN Bridge

Verify that the database is really encrypted:

    $ echo .dump | sqlite3 ~/.config/git-svn-auth-manager/userinfo.db
    PRAGMA foreign_keys=OFF;
    BEGIN TRANSACTION;
    /**** ERROR: (26) file is encrypted or is not a database *****/
    ROLLBACK; -- due to errors

Create configuration files and enable email notifications to users for
*Subversion* authentication failures (*substitute YOURGMAILPASSWORD with
real GMail password, the credentials will be used to authenticate
GMail SMTP connections*):

    $ make install_config
    ...
    install -m 600 -D config-just-enough ~/.config/git-svn-auth-manager/config
    $ GITSVNAUTHMGRCONF="$HOME/.config/git-svn-auth-manager/config"
    $ sed -i "s/username@gmail.com/${YOUR_EMAIL}/" "$GITSVNAUTHMGRCONF"
    $ sed -i 's/userpassword/YOURGMAILPASSWORD/' "$GITSVNAUTHMGRCONF"

    $ cat "$GITSVNAUTHMGRCONF"
    <?xml version="1.0" encoding="utf-8"?>
    <configuration>
      <appSettings>
        <add key="mail_sending_enabled" value="true" />
        <add key="smtp_username" value="YOUREMAIL@gmail.com" />
        <add key="smtp_password" value="YOURGMAILPASSWORD" />
      </appSettings>
    </configuration>

Test that email sending works (the invalid SVN repository URL triggers
an error that will cause the email to be sent):

    $ ~/bin/git-svn-auth-manager -r ${YOUR_EMAIL} non-existing-path
    git-svn-auth-manager: error email sent
    git-svn-auth-manager: System.ApplicationException: Error executing `svn info --username "git-svn-bridge" --password "*****" "non-existing-path"`:
    svn: 'non-existing-path' is not a working copy

Verify that the error email arrives to your mailbox. It should look like [this
sample](https://github.com/mrts/git-svn-bridge/blob/master/git-svn-auth-manager/mail-sample.txt).

#### synchronize-git-svn.sh

Start by copying the script and sample configuration to `~/bin`:

    $ cd ~/bin
    $ cp ../git/github-git-svn-bridge-utils/scripts/synchronize-git-svn.sh .
    $ cp ../git/github-git-svn-bridge-utils/scripts/synchronize-git-svn.sh.config .

And test it all:

    $ ./synchronize-git-svn.sh

    $ cd ~/git/git-central-repo-clone
    $ git pull --rebase
    $ echo "void more_do_nothing() { }" >> src/main.cpp
    $ git commit -am "Add more_do_nothing() to main.cpp"
    [master 0c6e72a] Add more_do_nothing() to main.cpp
     1 file changed, 1 insertion(+)
    $ git push
    Counting objects: 7, done.
    Compressing objects: 100% (2/2), done.
    Writing objects: 100% (4/4), 374 bytes, done.
    Total 4 (delta 0), reused 0 (delta 0)
    Unpacking objects: 100% (4/4), done.
    To /home/git-svn-bridge/git/git-central-repo-trunk.git
       001c5c9..0c6e72a  master -> master

|**Note**|
|--------|
|If you see *Not a git repository* errors during push, then this is caused by problems with some versions of *Git*, please update *Git* as described above|

We are done with the setup now and will proceed with semi-realistic
virtual developer testing in the next section.

Test synchronization
--------------------

The scenario:

-   Alice commits to *trunk* in *Subversion*

-   Bob commits to *trunk* in *Subversion*

-   Carol commits a number of changes directly to *master* and pushes in *git*
    (triggers synchronization with the update hook)

-   Dave works on the task branch *payment-support*, merges it to *master* and
    pushes in *git* (triggers synchronization with the update hook)

-   Finally, *cron* triggers synchronization explicitly.

Let's setup the stage:

    $ cd ~/test
    $ mkdir {alice,bob,carol,dave}

    $ for name in alice bob; do
        echo "Use '$name' as password and '$name@company.com' as email"
        ~/bin/git-svn-auth-manager -a $name
        pushd $name
        svn --username $name --password $name co $SVN_REPO_URL
        popd
    done

    $ for name in carol dave; do
        echo "Use '$name' as password and '$name@company.com' as email"
        ~/bin/git-svn-auth-manager -a $name
        pushd $name
        git clone ~/git/git-central-repo-trunk.git git-trunk
        cd git-trunk
        git config user.name `~/bin/git-svn-auth-manager $name | sed 's/ <.*//'`
        git config user.email `~/bin/git-svn-auth-manager $name | sed 's/.*<\(.*\)>/\1/'`
        popd
    done

    $ cat > alice.sh << 'EOT'
    #!/bin/bash
    pushd alice/trunk
    echo 'void alice() { }' >> src/alice.cpp
    svn --username alice --password alice up
    svn add src/alice.cpp
    svn --username alice --password alice ci -m "Protect the global cache with a mutex"
    popd
    EOT

    $ cat > bob.sh << 'EOT'
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

    $ cat > carol.sh << 'EOT'
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

    $ cat > dave.sh << 'EOT'
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

    $ cat > cron.sh << 'EOT'
    #!/bin/bash
    ~/bin/synchronize-git-svn.sh CRON
    EOT

    $ chmod 755 *.sh

    $ cat > Makefile << 'EOT'
    all: alice bob carol dave cron
    .PHONY: all alice bob carol dave cron

    EOT

    $ for name in alice bob carol dave cron; do
        echo -e "${name}:\n\t./${name}.sh\n" >> Makefile
    done

And now we let our imaginary developers loose to the source control land:

    make

Or, to test that mutual exclusion works, run the scripts in parallel:

    make -j 5

Finally, shut down ``svnserve``:

    make -f ~/svn/Makefile svnserve-stop

Verify that all went well (you should see clean history according to the
examples in the *Overview* section):

    $ cd ~/svn/svn-checkout
    $ svn up
    $ svn log

    $ cd ~/git/git-central-repo-clone
    $ git pull --rebase
    $ git log

Test setting up repos for other branches
----------------------------------------

    $ make -f ~/svn/Makefile svnserve-start

    $ cd ~/svn/svn-checkout
    $ svn mkdir branches
    $ svn cp trunk branches/1.x
    $ svn ci -m "Branch trunk to 1.x"

    $ cd ~/git
    $ ./github-git-svn-bridge-utils/scripts/setup-svn-branch-git-bridge.sh
    $ git clone central-repo-1.x.git central-repo-1.x-clone
    $ cd central-repo-1.x-clone
    $ git log
    commit 095e7a01f102f79224df4283a67c4624986679a1
    Author: git-svn-bridge@company.com <git-svn-bridge@company.com>
    Date:   Sun Aug 26 18:38:34 2012 +0000

        Branch trunk to 1.x

        git-svn-id: svn://localhost/branches/1.x@10 1db59d55-421c-46dd...

    $ make -f ~/svn/Makefile svnserve-stop
