package encryption

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/hex"
)

var key = []byte("@KEY000000000000000000000000KEY@")
var nonce = []byte("000000000000") // 12 x "0"

// Encrypt encrypts values based on key defined elsewhere
func Encrypt(data string) string {
	plaintext := []byte(data)

	block, err := aes.NewCipher(key)
	if err != nil {
		panic(err.Error())
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		panic(err.Error())
	}
	return hex.EncodeToString(gcm.Seal(nil, nonce, plaintext, nil))
}

// Decrypt decrypts values based on key defined elsewhere
func Decrypt(data string) string {
	ciphertext, _ := hex.DecodeString(data)

	block, err := aes.NewCipher(key)
	if err != nil {
		panic(err.Error())
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		panic(err.Error())
	}

	plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		panic(err.Error())
	}
	return string(plaintext)
}
