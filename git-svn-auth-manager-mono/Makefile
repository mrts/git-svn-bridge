BINDIR = bin
OBJDIR = obj
TARGETNAME = git-svn-auth-manager

TARGET = $(BINDIR)/$(TARGETNAME)

# Creates a bundled binary and links SQLCipher statically into it
#
# See http://github.com/mrts/mono-static-linking for explanations
# and Mac build instructions.

# C# application
CSHARPC = dmcs
CSHARPEXECUTABLE = $(OBJDIR)/GitSvnAuthManager.exe
CSHARPREFERENCES = /r:System.dll /r:System.Data.dll /r:System.Configuration.dll
CSHARPFLAGS = /nologo /warn:4 /optimize+ /codepage:utf8 /t:exe \
	/define:WITH_STATICALLY_LINKED_SQLCIPHER_SQLITE
CHARPSRC = $(wildcard src/*.cs)

# mkbundle
CC = cc
CFLAGS = -Wall -s -O2 -Wl,-O1
GENERATEDSRC = $(OBJDIR)/hello-gen.c
BUNDLEOBJS = $(OBJDIR)/hello-bundles.o

# SQLCipher C library
SQLCIPHERDIR = sqlcipher
SQLCIPHERLIB = $(SQLCIPHERDIR)/.libs/libsqlite3.a
SQLCIPHERCONFIGFLAGS = --enable-tempstore=yes \
	CFLAGS="-DSQLITE_HAS_CODEC -DSQLITE_ENABLE_COLUMN_METADATA" \
	LDFLAGS="-lcrypto"

# targets

all: $(TARGET)

$(TARGET): $(GENERATEDSRC) $(SQLCIPHERLIB) | $(BINDIR)
	$(CC) -o $(TARGET) $(CFLAGS) $(GENERATEDSRC) \
		-rdynamic \
		-Wl,-whole-archive \
		$(SQLCIPHERLIB) \
		-Wl,-no-whole-archive \
		$(BUNDLEOBJS) \
		`pkg-config --cflags --libs mono-2` \
		`pkg-config --libs openssl`

$(GENERATEDSRC): $(CSHARPEXECUTABLE)
	mkbundle -c -o $(GENERATEDSRC) -oo $(BUNDLEOBJS) $(CSHARPEXECUTABLE)

$(SQLCIPHERLIB): $(SQLCIPHERDIR)/Makefile
	cd $(SQLCIPHERDIR); \
	make -j 4

$(SQLCIPHERDIR)/Makefile: $(SQLCIPHERDIR)/configure
	cd $(SQLCIPHERDIR); \
	./configure $(SQLCIPHERCONFIGFLAGS)

$(CSHARPEXECUTABLE): $(CHARPSRC) | $(OBJDIR)
	$(CSHARPC) "/out:$(CSHARPEXECUTABLE)" \
		$(CSHARPREFERENCES) $(CSHARPFLAGS) $(CHARPSRC)

install: $(TARGET)
	install -m 711 -D $(TARGET) ~/bin/$(TARGETNAME)

install_config: install
	install -m 600 -D config-just-enough ~/.config/$(TARGETNAME)/config

$(OBJDIR):
	mkdir -p $(OBJDIR)

$(BINDIR):
	mkdir -p $(BINDIR)

clean:
	rm -rf $(OBJDIR) $(BINDIR)

mrproper: clean
	rm -f ~/.config/$(TARGETNAME)/userinfo.db
	cd $(SQLCIPHERDIR); git clean -fdx
