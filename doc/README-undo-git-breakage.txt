Reset central repo's history to what's currently in SVN:

git-svn-gateway.git$ git svn fetch
git-svn-gateway.git$ git checkout master
git-svn-gateway.git$ git reset --hard svn/git-svn
git-svn-gateway.git$ git push git-central-repo master

(probably fails, so
git-svn-gateway.git$ git push --force git-central-repo master)
