package utils

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"log"
	"os"

	"golang.org/x/crypto/ssh/terminal"
)

// ReadPasswordFromTerminal is used to read password and verify its value or return
// error on missmatch
func ReadPasswordFromTerminal() (string, error) {
	fmt.Print("Enter Password: ")
	password, err := terminal.ReadPassword(0)
	if err != nil {
		log.Fatal(err)
		os.Exit(1)
	}
	fmt.Println()
	fmt.Print("Verify Password: ")
	passwordVerify, err := terminal.ReadPassword(0)
	if err != nil {
		log.Fatal(err)
		os.Exit(1)
	}
	fmt.Println()
	if bytes.Equal(password, passwordVerify) {
		return string(password), nil
	}
	return "", errors.New("Passwords do not match")

}

// ReadDataFromTerminal is used to read data from terminal
// with provided text as prompt
func ReadDataFromTerminal(input, original string) (string, error) {
	var prompt string
	if len(original) > 0 {
		prompt = fmt.Sprintf("Enter %s [%s]: ", input, original)
	} else {
		prompt = fmt.Sprintf("Enter %s: ", input)
	}
	fmt.Print(prompt)
	reader := bufio.NewReader(os.Stdin)
	text, _, err := reader.ReadLine()
	if err != nil {
		log.Fatalf("Error on reading %s...", prompt)
		return "", err
	}
	if len(text) == 0 {
		return original, nil
	}
	return string(text), nil
}
