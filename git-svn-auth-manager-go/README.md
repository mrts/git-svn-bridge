git/Subversion authentication and user information manager
==========================================================

Helper utility for running a git-SVN bridge.

- Manages SVN authentication for git
- User mapping between git and SVN
- Keeps data in an encrypted database
- Sends email notifications when SVN authentication fails

Database is in:

  ~/.config/git-svn-auth-manager/userinfo.db

Usage
-----

Run either with a single non-option argument to output user
name and email suitable for `git --authors-prog`

 git-svn-auth-manager USERNAME

or with a single option to invoke option-specific behaviour:
```
git-svn-auth-manager
Provides mapping between git and svn repository users

Usage:
  git-svn-auth-manager [flags]
  git-svn-auth-manager [command]

Available Commands:
  config      set parameters
  help        Help about any command

Flags:
  -a, --add-user string            Add user information to the database
  -p, --change-passwd-for string   Change user's password in the database
  -c, --config-file string         Config file location
  -h, --help                       help for git-svn-auth-manager
  -r, --reset-auth-for string      Reset SVN auth cache with user's credentials; SVN URL required as non-option argument

Use "git-svn-auth-manager [command] --help" for more information about a command.
```

Building
--------

As this software is written in golang you can run:
```
go get github.com/bmanojlovic/git-svn-bridge/tree/master/git-svn-auth-manager
```

**Change key**, build:

```
 $ cd git-svn-bridge/git-svn-auth-manager/GitSvnAuthManager
 $ ENCRYPTION_KEY=`tr -dc '[:alnum:]' < /dev/urandom | head -c 32`
 $ sed -i "s/@KEY000000000000000000000000KEY@/$ENCRYPTION_KEY/" encryption/encryption.go
 $ make
 $ cp git-svn-auth-manager ~/bin/git-svn-auth-manager
 ```


Security
--------

Database is encrypted.

As encryption key is embedded in `git-svn-auth-manager`, it needs to be owned
by root and be made execute-only:

```
 $ sudo chown root: git-svn-auth-manager
 $ chmod 711 git-svn-auth-manager
```

Configuration
-------------

Config is in:

  ~/.config/git-svn-auth-manager/config.yml

Configuration settings (from `git-svn-auth-manager -h`):

    svn_auth_dir: SVN authentication cache folder
        (default: ${HOME}/.subversion/auth)

    db_filename: encrypted user info database location
        (default: ${ApplicationData}/git-svn-auth-manager/userinfo.db,
         ${ApplicationData} is ${HOME}/.config in Linux)

    mail_sending_enabled: if "true", send error mails to users
        when `svn info` fails (default: false);
        if mail_sending_enabled is true,
        the following additional settings apply:

            smtp_username: SMTP username (NO DEFAULT)

            smtp_password: SMTP password (NO DEFAULT)

            smtp_server_host: SMTP server host name (default: smtp.gmail.com)

            smtp_server_port: SMTP server port (default: 587)

            mail_from: mail From: header (default: ${smtp_username})

            mail_subject: mail Subject: header
                (default: built-in ${MAIL_SUBJECT_DEFAULT})

            mail_body: mail message body, must have {}-placeholders for
                user name, application name, SVN username and error message
                (default: built-in ${MAIL_BODY_DEFAULT})

            do_not_check_server_certificate: if "true", do not check SMTP
                server certificate
                (default: true, i.e. certificate is NOT checked)


See config_full.yml-full for a full sample or
config_full.yml-sensible for enabling mail sending (other settings
can be left to defaults if GMail is used).

Mail sending
-------------

See mail-sample.txt for the mail template that is used by default.

Enable email notifications to users for *Subversion* authentication failures
(**substitute sed replacment strings with real GMail account data**):

```
 $ sed -i 's/username@gmail.com/REAL_GMAIL_USER/' config_full.yml
 $ sed -i 's/password/REAL_GMAIL_PASSWORD/' config_full.yml
```