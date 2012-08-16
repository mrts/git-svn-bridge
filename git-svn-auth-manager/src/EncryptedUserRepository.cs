using System;
using System.IO;
using System.Data;

namespace GitSvnAuthManager
{
	internal sealed class EncryptedUserRepository
	{
		// Encryption key is intentionally compiled into the binary
		// providing additional security-by-obscurity protection for the database;
		// see the main README.rst for the rationale
		private const string ENCRYPTION_KEY = "CHANGETHIS";
		private readonly EncryptedSQLiteDb _db;
		private static readonly Lazy<EncryptedUserRepository> _instance = new Lazy<EncryptedUserRepository> (() => new EncryptedUserRepository ());

		public static EncryptedUserRepository Instance
		{ get { return _instance.Value; } }

		private EncryptedUserRepository ()
		{
			string db_filename = Config.Settings ["db_filename"];

			if (db_filename == null) {
				string configdir = Config.ConfigDir;

				if (!Directory.Exists (configdir))
					Directory.CreateDirectory (configdir);

				db_filename = Path.Combine (configdir, "userinfo.db");
			}

			_db = new EncryptedSQLiteDb (db_filename);

			_db.ExecuteUpdate (String.Format ("PRAGMA key='{0}'", ENCRYPTION_KEY.Replace ('\'', '.')));

			_db.ExecuteUpdate ("CREATE TABLE IF NOT EXISTS user" +
				"(svn_username TEXT UNIQUE NOT NULL, " +
				"email TEXT UNIQUE NOT NULL, " +
				"name TEXT NOT NULL, " +
				"svn_password TEXT NOT NULL)");
		}

		public void Save (User user)
		{
			_db.ExecuteUpdate ("INSERT OR REPLACE INTO user (svn_username, email, name, svn_password)" +
			                   "VALUES (?, ?, ?, ?)", user.svn_username, user.email, user.name, user.svn_password);
		}

		public User LoadBySvnUsername (string svn_username)
		{
			using (DataTable records = _db.ExecuteQuery ("SELECT * FROM user WHERE svn_username = ?", svn_username)) {
				return LoadFromDataTable (records, "user " + svn_username);
			}
		}

		public User LoadByEmail (string email)
		{
			using (DataTable records = _db.ExecuteQuery ("SELECT * FROM user WHERE email = ?", email)) {
				return LoadFromDataTable (records, "email " + email);
			}
		}

		private User LoadFromDataTable (DataTable records, string entity)
		{
			if (records.Rows.Count == 0)
				throw new ApplicationException (Char.ToUpper (entity [0]) + entity.Substring (1) + " not in database");
			if (records.Rows.Count > 1)
				throw new ApplicationException ("Multiple records of " + entity + "in database");

			return new User (records.Rows [0]);
		}
	}
}

