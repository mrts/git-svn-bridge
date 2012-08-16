using System;
using System.Configuration;
using System.Reflection;
using System.IO;

namespace GitSvnAuthManager
{
	internal static class Config
	{
		private static readonly Lazy<Configuration> _config = new Lazy<Configuration> (() => {
			ExeConfigurationFileMap config_map = new ExeConfigurationFileMap ();
			config_map.ExeConfigFilename = Path.Combine (ConfigDir, "config");

			return ConfigurationManager.OpenMappedExeConfiguration (config_map, ConfigurationUserLevel.None);
		});
		private static readonly Lazy<string> _config_dir = new Lazy<string> (() => {
			string appdata_dir = Environment.GetFolderPath (Environment.SpecialFolder.ApplicationData);
			object[] attrs = System.Reflection.Assembly.GetExecutingAssembly ().GetCustomAttributes (typeof(AssemblyProductAttribute), false);
			// in general attrs could be null or Length == 0, but we have the set in AssemblyInfo.cs
			string product_name = ((AssemblyProductAttribute)attrs [0]).Product;

			return Path.Combine (appdata_dir, product_name);
		});

		internal interface IConfigKeyValueCollection
		{
			string this [string key] {
				get;
			}
		}

		private class SettingsHelper : IConfigKeyValueCollection
		{
			private readonly KeyValueConfigurationCollection _settings;

			public SettingsHelper (KeyValueConfigurationCollection settings)
			{
				_settings = settings;
			}

			public string this [string key] {
				get {
					var element = _settings [key];
					return element == null ? null : element.Value;
				}
			}
		}

		public static string ConfigDir {
			get { return _config_dir.Value; }
		}

		public static IConfigKeyValueCollection Settings {
			get { return new SettingsHelper (_config.Value.AppSettings.Settings); }
		}
	}
}
