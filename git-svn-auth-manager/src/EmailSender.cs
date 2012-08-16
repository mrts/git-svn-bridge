using System;
using System.Net.Mail;
using System.Net;
using System.Security.Cryptography.X509Certificates;
using System.Net.Security;

namespace GitSvnAuthManager
{
	internal static class EmailSender
	{
		private const string SMTP_SERVER_HOST_DEFAULT = "smtp.gmail.com";
		private const string SMTP_SERVER_PORT_DEFAULT = "587";
		private const string MAIL_SUBJECT_DEFAULT = "[{0}] SVN ACCESS ERROR";
		private const string MAIL_BODY_DEFAULT = @"Hi {0}!

An error occurred while accessing SVN with your credentials.
Either your credentials are wrong or the SVN repository is down.

If your password has changed, then please update it with

 {1} --change-passwd-for {2}

in the git-svn bridge host or ask for help from the person who manages it.

Details:
--------------------------------------------------------------------------
{3}
--------------------------------------------------------------------------

Best,
{1}";

		public static bool IsEmailValid (string email)
		{
			try {
				new MailAddress (email);
			} catch (FormatException) {
				return false;
			}
			return true;
		}

		public static bool SendErrorEmail (User user, string error)
		{
			var settings = Config.Settings;

			if ((settings ["mail_sending_enabled"] ?? "false") == "false")
				return false;

			string smtp_username = settings ["smtp_username"];
			string smtp_password = settings ["smtp_password"];

			string smtp_server_host = settings ["smtp_server_host"] ?? SMTP_SERVER_HOST_DEFAULT;
			string smtp_server_port = settings ["smtp_server_port"] ?? SMTP_SERVER_PORT_DEFAULT;

			string mail_from = settings ["mail_from"] ?? smtp_username;
			string mail_subject = settings ["mail_subject"] ?? String.Format (MAIL_SUBJECT_DEFAULT, MainClass.APP_NAME);
			string mail_body = settings ["mail_body"] ?? MAIL_BODY_DEFAULT;

			MailMessage message = new MailMessage (mail_from, user.email, mail_subject,
			                                       String.Format (mail_body, user.name, MainClass.APP_NAME,
			                                                      user.svn_username, error));

			SmtpClient smtp = new SmtpClient (smtp_server_host, Convert.ToInt32 (smtp_server_port));
			smtp.Credentials = new NetworkCredential (smtp_username, smtp_password);
			smtp.EnableSsl = true;

			// importing the GMail certificate is a hassle, see http://stackoverflow.com/a/9803922
			if ((settings ["do_not_check_server_certificate"] ?? "true") == "true")
				ServicePointManager.ServerCertificateValidationCallback = delegate(object s, X509Certificate certificate, X509Chain chain, SslPolicyErrors sslPolicyErrors) {
					return true; };

			smtp.Send (message);
			return true;
		}
	}
}
