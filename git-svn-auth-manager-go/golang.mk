# Source: https://github.com/rebuy-de/golang-template
# Version: 2.0.2-snapshot
# Dependencies:
# * dep (https://github.com/golang/dep)
# * gocov (https://github.com/axw/gocov)
# * gocov-html (https://github.com/matm/gocov-html)

NAME=$(notdir $(PACKAGE))

BUILD_VERSION=$(shell git describe --always --dirty --tags | tr '-' '.' )
BUILD_DATE=$(shell date)
BUILD_HASH=$(shell git rev-parse HEAD)
BUILD_MACHINE=$(shell echo $$HOSTNAME)
BUILD_USER=$(shell whoami)
BUILD_ENVIRONMENT=$(BUILD_USER)@$(BUILD_MACHINE)

BUILD_XDST=$(PACKAGE)/vendor/github.com/rebuy-de/rebuy-go-sdk/cmdutil
BUILD_FLAGS=-ldflags "\
	$(ADDITIONAL_LDFLAGS) \
	-X '$(BUILD_XDST).BuildName=$(NAME)' \
	-X '$(BUILD_XDST).BuildPackage=$(PACKAGE)' \
	-X '$(BUILD_XDST).BuildVersion=$(BUILD_VERSION)' \
	-X '$(BUILD_XDST).BuildDate=$(BUILD_DATE)' \
	-X '$(BUILD_XDST).BuildHash=$(BUILD_HASH)' \
	-X '$(BUILD_XDST).BuildEnvironment=$(BUILD_ENVIRONMENT)' \
"

GOFILES=$(shell find . -type f -name '*.go' -not -path "./vendor/*")
GOPKGS=$(shell go list ./...)

default: build

Gopkg.lock: Gopkg.toml
	dep ensure
	touch Gopkg.lock

vendor: Gopkg.lock Gopkg.toml
	dep ensure
	touch vendor

format:
	gofmt -s -w $(GOFILES)

vet: vendor
	go vet $(GOPKGS)

lint:
	$(foreach pkg,$(GOPKGS),golint $(pkg);)

test_gopath:
	test $$(go list) = "$(PACKAGE)"

test_packages: vendor
	go test $(GOPKGS)

test_format:
	gofmt -s -l $(GOFILES)

test: test_gopath test_format vet lint test_packages

cov:
	gocov test -v $(GOPKGS) \
		| gocov-html > coverage.html

build:
	go build \
		$(BUILD_FLAGS) \
		-o $(NAME)-$(BUILD_VERSION)-$(shell go env GOOS)-$(shell go env GOARCH)$(shell go env GOEXE)
	ln -sf $(NAME)-$(BUILD_VERSION)-$(shell go env GOOS)-$(shell go env GOARCH)$(shell go env GOEXE) $(NAME)$(shell go env GOEXE)

xc:
	GOOS=linux GOARCH=amd64 make build
	GOOS=darwin GOARCH=amd64 make build
	GOOS=windows GOARCH=386 make build
	GOOS=windows GOARCH=amd64 make build

install: test
	go install \
		$(BUILD_FLAGS)

clean:
	rm -f $(NAME)*

.PHONY: build install test
