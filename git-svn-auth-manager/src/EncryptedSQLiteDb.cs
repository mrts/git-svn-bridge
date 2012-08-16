using System;
using System.Data;
using System.IO;
using System.Runtime.InteropServices;

namespace GitSvnAuthManager
{
	// TODO: IDisposable
	internal sealed class EncryptedSQLiteDb
	{
#if WITH_STATICALLY_LINKED_SQLCIPHER_SQLITE
#warning PREPARING CODE FOR STATICALLY LINKED SQLIPHER SQLITE
		// To make the runtime lookup symbols in the current executable
		// when using static linking,
		// use the special library name "__Internal"
		internal const string SQLITE_DLL = "__Internal";
#else
		public const string SQLITE_DLL = "sqlite3";
#endif
		private IntPtr _db = IntPtr.Zero;

		public EncryptedSQLiteDb (string db_filename)
		{
			if (SQLiteNativeMethods.sqlite3_open16 (db_filename, out _db) != SQLITE_OK)
				throw new ApplicationException ("Failed to open database " + db_filename);
		}

		~EncryptedSQLiteDb ()
		{
			if (_db != IntPtr.Zero)
				SQLiteNativeMethods.sqlite3_close (_db);
		}

		public DataTable ExecuteQuery (string query, params string[] args)
		{
			IntPtr statement = PrepareStatement (query, args);

			DataTable result = new DataTable ();

			try {
				int column_count = SQLiteNativeMethods.sqlite3_column_count (statement);

				for (int i = 0; i < column_count; i++) {
					IntPtr col_name = SQLiteNativeMethods.sqlite3_column_origin_name16 (statement, i);
					result.Columns.Add (UniPtrToString (col_name), typeof(string));
				}

				while (SQLiteNativeMethods.sqlite3_step(statement) == SQLITE_ROW) {
					string[] row = new string[column_count];

					for (int i = 0; i < column_count; i++) {
						if (SQLiteNativeMethods.sqlite3_column_type (statement, i) != TypeAffinity.Text)
							throw new ApplicationException (String.Format ("Column {0} is not string", i));
						IntPtr val = SQLiteNativeMethods.sqlite3_column_text16 (statement, i);
						row [i] = UniPtrToString (val) ?? "";
					}

					result.Rows.Add (row);
				}

			} finally {
				FinalizeStatement (statement);
			}

			return result;
		}

		public void ExecuteUpdate (string query, params string[] args)
		{
			IntPtr statement = PrepareStatement (query, args);
			try {
				if (SQLiteNativeMethods.sqlite3_step (statement) != SQLITE_DONE)
					throw new ApplicationException ("Execute update result not DONE: " + ErrMsg ());
			} finally {
				FinalizeStatement (statement);
			}
		}
		
		private string UniPtrToString (IntPtr str)
		{
			return Marshal.PtrToStringUni (str);
		}

		private string ErrMsg ()
		{
			IntPtr msg_ptr = SQLiteNativeMethods.sqlite3_errmsg16 (_db);
			return UniPtrToString (msg_ptr) ?? "";
		}

		private IntPtr PrepareStatement (string query, params string[] args)
		{
			IntPtr statement;

			if (SQLiteNativeMethods.sqlite3_prepare16_v2 (_db, query, query.Length * 2, out statement, IntPtr.Zero) != SQLITE_OK)
				throw new ApplicationException (ErrMsg ());

			for (int i = 1; i <= args.Length; i++) {
				string arg = args [i - 1];
				if (SQLiteNativeMethods.sqlite3_bind_text16 (statement, i, arg, arg.Length * 2, -1) != SQLITE_OK)
					throw new ApplicationException (ErrMsg ());
			}

			return statement;
		}

		private void FinalizeStatement (IntPtr statement)
		{
			if (SQLiteNativeMethods.sqlite3_finalize (statement) != SQLITE_OK)
				throw new ApplicationException (ErrMsg ());
		}

		private const int SQLITE_OK = 0;
		private const int SQLITE_ROW = 100;
		private const int SQLITE_DONE = 101;
	}
}
