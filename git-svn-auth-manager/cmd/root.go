// Copyright © 2018 Boris Manojlovic <boris@steki.net>
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package cmd

import (
	"crypto/tls"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"

	db "github.com/bmanojlovic/git-svn-bridge/git-svn-auth-manager/db"
	utils "github.com/bmanojlovic/git-svn-bridge/git-svn-auth-manager/utils"
	homedir "github.com/mitchellh/go-homedir"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"gopkg.in/gomail.v2"
)

var commandToExecute, home, flagConfigFile, flagUserToAdd, flagChangePwFor, flagresetAuthFor string

var rootCmd = &cobra.Command{
	Use:   "git-svn-auth-manager",
	Short: "Provides mapping between git and svn repository users",
	Args:  cmdArgs,
	Run:   cmdRun,
}

func cmdArgs(cmd *cobra.Command, args []string) error {
	switch {
	case flagUserToAdd != "":
		return runAddUser()
	case flagChangePwFor != "":
		return runChangePw()
	case flagresetAuthFor != "":
		if len(args) != 1 {
			return errors.New("subversion URL argument required")
		}
		return runResetAuthFor(args[0])
	case len(args) == 1:
		svnUserToGitAuthor(args[0])
		return nil
	default:
		// we assume everything is parsed correctly so just show help
		// to user by default when there is no flags or commands
		return cmd.Help()
	}
}

func init() {
	cobra.OnInitialize(initConfig)
	rootCmd.PersistentFlags().StringVarP(&flagConfigFile, "config-file", "c", "", "Config file location")
	rootCmd.Flags().StringVarP(&flagUserToAdd, "add-user", "a", "", "Add user information to the database")
	rootCmd.Flags().StringVarP(&flagChangePwFor, "change-passwd-for", "p", "", "Change user's password in the database")
	rootCmd.Flags().StringVarP(&flagresetAuthFor, "reset-auth-for", "r", "", "Reset SVN auth cache with user's credentials;"+
		" SVN URL required as non-option argument")
}

// initConfig reads in config file and Connect to database
func initConfig() {
	if flagConfigFile != "" {
		// Use config file from the flag.
		viper.SetConfigFile(flagConfigFile)
	} else {
		// Find home directory.
		home, err := homedir.Dir()
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}
		// Search config in home directory with name "config" (without extension).
		// viper.AddConfigPath(home)
		viper.AddConfigPath(home + "/.config/git-svn-auth-manager/")
		viper.SetConfigName("config")
	}
	viper.SetConfigType("yaml")
	viper.AutomaticEnv() // read in environment variables that match

	// If a config file is found, read it in.
	err := viper.ReadInConfig()
	if err != nil {
		fmt.Println("Error Using config file:", viper.ConfigFileUsed())
		fmt.Println(err)
	}
	// try connecting to database
	db.Connect(viper.GetString("configuration.appSettings.db_filename"))
}

func cmdRun(cmd *cobra.Command, args []string) {
}

// runAddUser adds or modify user in database
func runAddUser() error {
	var err error
	var answer string
	user := db.GITSVNUser{}
	fromDB := db.GetByUserName(flagUserToAdd)
	if strings.Compare(fromDB.SVNUsername, flagUserToAdd) == 0 {
		if answer, err = utils.ReadDataFromTerminal("User "+flagUserToAdd+" already exist do you want to update it? [y/n]", ""); answer != "y" {
			log.Infoln("User data unchanged")
			os.Exit(0)
		}
	}
	user.SVNUsername = flagUserToAdd
	user.Name, err = utils.ReadDataFromTerminal("Name and Lastname", fromDB.Name)
	if err != nil {
		log.Fatalln(err)
	}
	user.Email, err = utils.ReadDataFromTerminal("Email", fromDB.Email)
	if err != nil {
		log.Fatalln(err)
	}
	user.SVNPassword, err = utils.ReadPasswordFromTerminal()
	if err != nil {
		log.Fatalln(err)
	}
	user.SVNUsername = flagUserToAdd

	db.UpSertUserData(&user)
	return nil
}

// runChangePw change SVN user password
func runChangePw() error {
	var err error
	fromDB := db.GetByUserName(flagChangePwFor)
	log.Debugf("%+v\n", fromDB)
	if strings.Compare(flagChangePwFor, fromDB.SVNUsername) == 0 {
		fromDB.SVNPassword, err = utils.ReadPasswordFromTerminal()
		if err == nil {
			db.UpSertUserData(&fromDB)
			return nil
		}
		return err
	}
	return errors.New("No such user in database")

}

// runResetAuthFor is used to update subversion authentication cache
func runResetAuthFor(urlSVN string) error {
	var promptUser, promptPass string
	u := db.GetByUserName(flagresetAuthFor)
	if strings.Compare(u.SVNUsername, flagresetAuthFor) != 0 {
		return errors.New("No such user in DB")
	}
	promptUser = "--username=" + u.SVNUsername
	promptPass = "--password=" + u.SVNPassword
	svnInfo := exec.Command("svn", "info", promptUser, promptPass, urlSVN)
	output, err := svnInfo.CombinedOutput()
	if err != nil {
		body := strings.Replace(viper.GetString("configuration.appSettings.mail_body"), "{0}", u.Name, -1)
		body = strings.Replace(body, "{1}", os.Args[0], -1)
		body = strings.Replace(body, "{2}", u.SVNUsername, -1)
		body = strings.Replace(body, "{3}", fmt.Sprint(svnInfo.Stderr), -1)
		m := gomail.NewMessage()
		m.SetHeader("From", viper.GetString("configuration.appSettings.mail_from"))
		m.SetHeader("To", u.Email)
		m.SetHeader("Subject", viper.GetString("configuration.appSettings.mail_subject"))
		m.SetBody("text/plain", body)
		portNum, _ := strconv.Atoi(viper.GetString("configuration.appSettings.smtp_server_port"))
		tlsVerify, _ := strconv.ParseBool(viper.GetString("configuration.appSettings.do_not_check_server_certificate"))
		d := gomail.Dialer{Host: viper.GetString("configuration.appSettings.smtp_server_host"), Port: portNum}
		d.TLSConfig = &tls.Config{InsecureSkipVerify: tlsVerify}
		if err := d.DialAndSend(m); err != nil {
			log.Fatal(err)
		}
		log.Error(svnInfo.Stderr)
		return nil
	}
	log.Debugln(output)
	return nil

}

// Execute adds all child commands to the root command and sets flags appropriately.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func svnUserToGitAuthor(svnuser string) error {
	if u := db.GetByUserName(svnuser); len(u.SVNUsername) != 0 {
		fmt.Printf("%s  <%s>\n", u.Name, u.Email)
		return nil
	}
	log.Fatalln("User " + svnuser + " does not exist in DB")
	return nil // not reached but required
}
