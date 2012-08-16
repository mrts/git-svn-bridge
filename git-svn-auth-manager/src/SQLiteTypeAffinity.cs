//
// Adopted from Mono.Data.Sqlite.SQLiteConvert.cs
//
// Author(s):
//   Robert Simpson (robert@blackcastlesoft.com)
//
// Adapted and modified for the Mono Project by
//   Marek Habersack (grendello@gmail.com)
//
//
// Copyright (C) 2006 Novell, Inc (http://www.novell.com)
// Copyright (C) 2007 Marek Habersack
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
// 
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

/********************************************************
 * ADO.NET 2.0 Data Provider for Sqlite Version 3.X
 * Written by Robert Simpson (robert@blackcastlesoft.com)
 * 
 * Released to the public domain, use at your own risk!
 ********************************************************/
namespace GitSvnAuthManager
{
	/// <summary>
	/// Sqlite has very limited types, and is inherently text-based.  The first 5 types below represent the sum of all types Sqlite
	/// understands.  The DateTime extension to the spec is for internal use only.
	/// </summary>
	public enum TypeAffinity
	{
		/// <summary>
		/// Not used
		/// </summary>
		Uninitialized = 0,
		/// <summary>
		/// All integers in Sqlite default to Int64
		/// </summary>
		Int64 = 1,
		/// <summary>
		/// All floating point numbers in Sqlite default to double
		/// </summary>
		Double = 2,
		/// <summary>
		/// The default data type of Sqlite is text
		/// </summary>
		Text = 3,
		/// <summary>
		/// Typically blob types are only seen when returned from a function
		/// </summary>
		Blob = 4,
		/// <summary>
		/// Null types can be returned from functions
		/// </summary>
		Null = 5
	}

}
