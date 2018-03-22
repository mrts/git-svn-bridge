using System;
using System.IO;
using System.Configuration;
using System.Diagnostics;
using System.Text.RegularExpressions;

namespace GitSvnAuthManager
{
	internal static class GitSvnAuthManager
	{
		public static void AddUser (string svn_username)
		{
			var user = new User (svn_username);

			Console.WriteLine ("Adding/overwriting SVN user " + svn_username);

			user.svn_password = GetPassword ();
			user.email = GetFromConsole ("Email");
			if (!EmailSender.IsEmailValid (user.email))
				throw new ApplicationException ("Invalid email: " + user.email);
			user.name = GetFromConsole ("Name");

			EncryptedUserRepository.Instance.Save (user);
		}

		public static void ChangePassword (string svn_username)
		{
			var user = EncryptedUserRepository.Instance.LoadBySvnUsername (svn_username);

			Console.WriteLine ("Changing SVN password for SVN user " + user.svn_username);

			user.svn_password = GetPassword ();

			EncryptedUserRepository.Instance.Save (user);
		}

		// Output "User Name <user@email.com>" for given SVN username
		// for using the application for `git --authors-prog`.
		public static void OutputForGitAuthorsProg (string svn_username)
		{
			var user = EncryptedUserRepository.Instance.LoadBySvnUsername (svn_username);

			Console.WriteLine ("{0} <{1}>", user.name, user.email);
		}

		// Reset SVN auth cache by running
		// 	`svn info --username "$USERNAME" --password "$PASSWORD" "$SVN_URL"`,
		// and send email to the user on failure (if mail sending is enabled)
		public static void ResetSubversionAuthCache (string email, string svn_url)
		{
			if (!EmailSender.IsEmailValid (email))
				throw new ApplicationException ("Invalid email: " + email);

			var user = EncryptedUserRepository.Instance.LoadByEmail (email);

			string svn_auth_dir = Config.Settings ["svn_auth_dir"] ??
				Path.Combine (Environment.GetFolderPath (Environment.SpecialFolder.Personal),
				".subversion", "auth");

			string svn_auth_dir_backup = svn_auth_dir + "." + MainClass.APP_NAME + "-backup";
			if (Directory.Exists (svn_auth_dir))
				Directory.Move (svn_auth_dir, svn_auth_dir_backup);

			string args = String.Format (@"info --non-interactive --username ""{0}"" --password ""{1}"" ""{2}""",
			                             QuoteForShell (user.svn_username), QuoteForShell (user.svn_password),
			                             QuoteForShell (svn_url));

			var svn_info_startinfo = new ProcessStartInfo ("svn", args);
			svn_info_startinfo.CreateNoWindow = true;
			svn_info_startinfo.UseShellExecute = false;
			svn_info_startinfo.RedirectStandardOutput = true;
			svn_info_startinfo.RedirectStandardError = true;

			using (Process svn_info = Process.Start (svn_info_startinfo)) {
				string stdout = svn_info.StandardOutput.ReadToEnd ();
				string stderr = svn_info.StandardError.ReadToEnd ();
				// TODO: timeout?
				svn_info.WaitForExit ();

				if (svn_info.ExitCode != 0) {
					string error = "Error executing `svn " +
						Regex.Replace (args, @"--password ""[^""]+""", @"--password ""*****""") + "`:\n"
							+ stdout + stderr;
					try {
						bool sending_successful = EmailSender.SendErrorEmail (user, error);
						if (sending_successful)
							Console.Error.WriteLine (MainClass.APP_NAME + ": error email sent");
					} catch (Exception e) {
						MainClass.ShowError (e, "Error while sending email: ");
					}

					// restore auth directory from backup or error
					Directory.Delete (svn_auth_dir, true);
					Directory.Move (svn_auth_dir_backup, svn_auth_dir);

					throw new ApplicationException (error);
				} else {
					Directory.Delete (svn_auth_dir_backup, true);
				}
			}
		}

		private static string GetFromConsole (string field)
		{
			Console.Write (field + ": ");
			string response = Console.ReadLine ();

			if (String.IsNullOrEmpty (response))
				throw new ApplicationException (field + " cannot be empty");

			return response;
		}

		private static string GetPassword ()
		{
			string passwd1 = GetFromConsole ("SVN password");
			string passwd2 = GetFromConsole ("SVN password (confirm)");

			if (passwd1 != passwd2)
				throw new ApplicationException ("Passwords don't match");

			return passwd1;
		}

		private static string QuoteForShell (string arg)
		{
			return arg.Replace ("\\", "\\\\").Replace ("\"", "\\\"");
		}
	}
}

