using System;
using System.IO;
using System.Collections.Generic;
using System.Configuration;

using Mono.Options;

namespace GitSvnAuthManager
{
	static class MainClass
	{
		internal const string APP_NAME = "git-svn-auth-manager";
		private const string OPT_ADD_USER = "add_user";
		private const string OPT_CHANGE_PASSWD = "change_passwd";
		private const string OPT_RESET_AUTH = "reset_auth";

		public static int Main (string[] args)
		{
			bool show_help = false;

			var options = new Dictionary<string, string> ();

			var option_set = new OptionSet () {
				{"help|h", "Show help",
					option => show_help = option != null},
				{"add-user=|a", "Add user information to the database",
					option => options [OPT_ADD_USER] = option},
				{"change-passwd-for=|p", "Change user's password in the database",
					option => options [OPT_CHANGE_PASSWD] = option},
				{"reset-auth-for=|r", "Reset SVN auth cache with user's credentials; option argument is user's email; SVN URL required as non-option argument",
					option => options [OPT_RESET_AUTH] = option}
			};

			List<string> non_option_arguments;
			try {
				non_option_arguments = option_set.Parse (args);
			} catch (Exception e) {
				ShowError (e);
				Console.Error.WriteLine ();
				ShowHelp (false, option_set);
				return 1;
			}

			if (show_help) {
				ShowHelp (true, option_set);
				return 0;
			}

			if (!(options.Count == 1 && non_option_arguments.Count <= 1 // RESET_AUTH takes SVN_URL as non-option argument
			                   || options.Count == 0 && non_option_arguments.Count == 1)) {
				Console.Error.WriteLine (APP_NAME + ": too few, too many or invalid arguments\n");
				ShowHelp (false, option_set);
				return 1;
			}

			if (options.Count == 0 && non_option_arguments.Count == 1) {
				string non_option_argument = non_option_arguments [0];
				if (non_option_argument.StartsWith ("-")) {
					Console.Error.WriteLine (APP_NAME + ": unknown option " + non_option_argument + "\n");
					ShowHelp (false, option_set);
					return 1;
				}

				return ExecuteAction (delegate {
					GitSvnAuthManager.OutputForGitAuthorsProg (non_option_argument);
				});
			}

			string the_option = new List<string> (options.Keys) [0];

			if (the_option != OPT_RESET_AUTH && non_option_arguments.Count == 1
			    || the_option == OPT_RESET_AUTH && non_option_arguments.Count == 0) {
				Console.Error.WriteLine (APP_NAME + ": A non-option argument is required for `reset-auth-for`, but forbidden for other options\n");
				ShowHelp (false, option_set);
				return 1;
			}

			if (the_option == OPT_RESET_AUTH && non_option_arguments.Count == 1)
				return ExecuteAction (delegate {
					GitSvnAuthManager.ResetSubversionAuthCache (options [the_option], non_option_arguments [0]);
				});

			// => the_option != RESET_AUTH && non_option_arguments.Count == 0

			var option_handlers = new Dictionary<string, Action<string>> () {
				{OPT_ADD_USER, GitSvnAuthManager.AddUser},
				{OPT_CHANGE_PASSWD, GitSvnAuthManager.ChangePassword}
			};

			return ExecuteAction (delegate {
				option_handlers [the_option] (options [the_option]); });
		}

		internal static void ShowError (Exception e, string message = "")
		{
			Console.Error.WriteLine (APP_NAME + ": " + message +
			                         e.GetType ().ToString () + ": " + e.Message);
		}

		private static int ExecuteAction (Action action)
		{
			try {
				action ();
			} catch (Exception e) {
				ShowError (e);
				return 1;
			}
			return 0;
		}

		private static void ShowHelp (bool help_requested, OptionSet options)
		{
			TextWriter writer = help_requested ? Console.Out : Console.Error;

			writer.WriteLine (String.Format (
@"Helper utility for running a git-SVN bridge.
Manages SVN authentication for git and user mapping between git and SVN.

Usage:
    either with a single non-option argument to output user
    name and email suitable for `git --authors-prog`:

        {0} SVN_USERNAME

    or with a single option to add users or change passwords:

        {0} OPTION=SVN_USERNAME

    or with a single option and single non-option argument to reset
    SVN authentication cache:

        {0} --reset-auth-for=EMAIL SVN_URL

Options:", APP_NAME));

			options.WriteOptionDescriptions (writer);

			if (help_requested) {
				writer.WriteLine (String.Format (
@"Configuration settings:

    svn_auth_dir: SVN authentication cache folder
        (default: ${{HOME}}/.subversion/auth)

    db_filename: encrypted user info database location
        (default: ${{ApplicationData}}/{0}/userinfo.db,
         ${{ApplicationData}} is ${{HOME}}/.config in Linux)

    mail_sending_enabled: if ""true"", send error mails to users
        when `svn info` fails (default: false);
        if mail_sending_enabled is true,
        the following additional settings apply:

            smtp_username: SMTP username (NO DEFAULT)

            smtp_password: SMTP password (NO DEFAULT)

            smtp_server_host: SMTP server host name (default: smtp.gmail.com)

            smtp_server_port: SMTP server port (default: 587)

            mail_from: mail From: header (default: ${{smtp_username}})

            mail_subject: mail Subject: header
                (default: built-in ${{MAIL_SUBJECT_DEFAULT}})

            mail_body: mail message body, must have {{}}-placeholders for
                user name, application name, SVN username and error message
                (default: built-in ${{MAIL_BODY_DEFAULT}})

            do_not_check_server_certificate: if ""true"", do not check SMTP
                server certificate
                (default: true, i.e. certificate is NOT checked)
", APP_NAME));
			}
		}
	}
}
