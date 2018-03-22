package db

import (
	"database/sql"
	"strings"

	enc "github.com/bmanojlovic/git-svn-bridge/git-svn-auth-manager/encryption"
	log "github.com/sirupsen/logrus"

	_ "github.com/mattn/go-sqlite3" //sqlite3 importing into main namespace
)

// GITSVNUser struct represent mapping for SQLite record
type GITSVNUser struct {
	SVNUsername string
	Email       string
	Name        string
	SVNPassword string
}

// Decrypt data in GITSVNUser struct
func (u *GITSVNUser) Decrypt() {
	u.SVNUsername = enc.Decrypt(u.SVNUsername)
	u.Email = enc.Decrypt(u.Email)
	u.Name = enc.Decrypt(u.Name)
	u.SVNPassword = enc.Decrypt(u.SVNPassword)
}

// DDLGitSvnBridge user schema for git-svn-bridge
var DDLGitSvnBridge = `CREATE TABLE IF NOT EXISTS user (
	svn_username TEXT UNIQUE NOT NULL, 
	email TEXT UNIQUE NOT NULL, 
	name TEXT NOT NULL, 
	svn_password TEXT NOT NULL
)`

// PSUpSertUserData prepared statement for adding and changing user data
var PSUpSertUserData = `INSERT OR REPLACE INTO user (
	svn_username,
	email,
	name,
	svn_password
) VALUES (?, ?, ?, ?)`

// PSGetUserData is prepared statement for getting data by email or svn_userename
var PSGetUserData = `SELECT * FROM user WHERE @@BY@@ = ?`

// DBHandle is database handle
var DBHandle *sql.DB

// DBError last DB error
var DBError error
var rows *sql.Rows
var res sql.Result

// Connect should be called first so it will create
// database file and initial schema if missing
func Connect(dbName string) bool {
	DBHandle, DBError = sql.Open("sqlite3", dbName)
	if DBError != nil {
		log.Fatal(DBError)
	}
	res, DBError = DBHandle.Exec(DDLGitSvnBridge)
	if DBError != nil {
		log.Printf("%q: %s\n", DBError, DDLGitSvnBridge)
		return false
	}
	log.Debugf("Connect: %+v\n", res)
	return true
}

// UpSertUserData is used to add/replace user data...
func UpSertUserData(u *GITSVNUser) {
	stmt, DBError := DBHandle.Prepare(PSUpSertUserData)
	if DBError != nil {
		log.Fatal(DBError)
	}
	defer stmt.Close()
	res, DBError = stmt.Exec(enc.Encrypt(u.SVNUsername), enc.Encrypt(u.Email), enc.Encrypt(u.Name), enc.Encrypt(u.SVNPassword))
	if DBError != nil {
		log.Fatal(DBError)
	}
	log.Debugf("Data struct %+v\n", u)
}

// GetByUserName select user details from DB by UserName
func GetByUserName(name string) GITSVNUser {
	return getData("svn_username", name)
}

// GetByEmail select user details from DB by Email
func GetByEmail(name string) GITSVNUser {
	return getData("email", name)
}

func getData(by, item string) GITSVNUser {
	var u GITSVNUser
	stmt, DBError := DBHandle.Prepare(strings.Replace(PSGetUserData, "@@BY@@", by, 1)) // this string replacement is safe as it is controlled by us
	if DBError != nil {
		log.Fatal(DBError)
	}
	defer stmt.Close()
	rows, DBError = stmt.Query(enc.Encrypt(item))
	if DBError != nil {
		log.Fatal(DBError)
	}
	for rows.Next() {
		DBError = rows.Scan(&u.SVNUsername, &u.Email, &u.Name, &u.SVNPassword)
		if DBError != nil {
			log.Fatal(DBError)
		}
	}
	if u.SVNUsername == "" {
		return GITSVNUser{}
	}
	u.Decrypt()
	return u
}
