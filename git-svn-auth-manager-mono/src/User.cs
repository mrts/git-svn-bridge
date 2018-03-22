using System;
using System.Data;

namespace GitSvnAuthManager
{
	internal sealed class User
	{
		public string svn_username { get; set; }

		public string email { get; set; }

		public string name { get; set; }

		public string svn_password { get; set; }

		public User (string svn_username)
		{
			this.svn_username = svn_username;
		}

		public User (DataRow record)
		{
			this.svn_username = (string)record ["svn_username"];
			this.email = (string)record ["email"];
			this.name = (string)record ["name"];
			this.svn_password = (string)record ["svn_password"];
		}
	}
}

