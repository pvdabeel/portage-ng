# Portage-ng
#
# Requires SWI-Prolog >= 10.0.0, preferably a development build.
# `make help` lists the targets.

SUDO                 = sudo
TARGET               = portage-ng
BUILDDIR             = $(shell pwd)

IPCCLIENT            = Source/Application/Wrapper/ipcclient
IPCCLIENT_SRC        = Source/Application/Client/ipcclient.cpp
CXX                 ?= c++
CXXFLAGS            ?= -O3 -Wall -march=native -Wextra
# C++17 stays on even when the environment overrides CXXFLAGS.
IPCCLIENT_CXXFLAGS   = $(CXXFLAGS) -std=c++17

CERTDIR              = Certificates
HOST                ?= $(shell hostname)

.PHONY: help check all build install test test-overlay ipcclient clean certs passwordfile certs-check certs-renew

# Show this help.
help:
	@awk '\
	  /^# / { desc = substr($$0, 3); next } \
	  /^[a-zA-Z0-9_.-]+:/ { \
	    if (desc != "") { \
	      tgt = $$1; sub(/:.*/, "", tgt); \
	      printf "%-16s %s\n", tgt ":", desc; \
	      desc = "" \
	    } \
	    next \
	  } \
	  { desc = "" } \
	' $(MAKEFILE_LIST)

# Verify development environment (SWI-Prolog, shell aliases).
check:
	@ok=true; \
	if ! command -v swipl >/dev/null 2>&1; then \
	  echo "ERROR: swipl not found in PATH."; \
	  echo "  Install SWI-Prolog >= 10.0.0: https://www.swi-prolog.org/download/devel"; \
	  ok=false; \
	else \
	  echo "OK: swipl found ($$(swipl --version 2>&1 | head -1))"; \
	fi; \
	if ! zsh -ic 'alias portage-ng-dev' >/dev/null 2>&1; then \
	  echo "WARNING: portage-ng-dev not found as alias."; \
	  echo "  Add the following to your ~/.zshrc or ~/.bash_profile:"; \
	  echo ""; \
	  echo "  alias portage-ng-dev=\"swipl -O \\\\"; \
	  echo "    --stack-limit=32G \\\\"; \
	  echo "    -f $(BUILDDIR)/portage-ng.pl \\\\"; \
	  echo "    -p portage=$(BUILDDIR) \\\\"; \
	  echo "    -Dverbose_autoload=false \\\\"; \
	  echo "    -g main --\""; \
	  echo ""; \
	  echo "  Then reload your shell: source ~/.zshrc or ~/.bash_profile"; \
	else \
	  echo "OK: portage-ng-dev alias found"; \
	fi; \
	if [ "$$ok" = false ]; then exit 1; fi

# Build and install.
all:
	check build install

# Build the application.
build:
	swipl -O --stack_limit=32G -o $(TARGET) -q -f portage-ng.pl -p portage=${BUILDDIR} -g main --stand_alone=true -c portage-ng.pl

# Install the application.
install:
	$(SUDO) cp $(TARGET) /usr/local/bin

# Run PLUnit tests.
test:
	printf '%s\n' \
	  "load_files(portage('Source/Test/unittest'), [if(true)])." \
	  "run_tests." \
	  "halt." | \
	  ./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell

# Run overlay regression tests (requires loaded overlay repository).
test-overlay:
	printf '%s\n' \
	  "test:run(cases)." \
	  "halt." | \
	  ./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell

# Build the native Unix-socket IPC client (C++ prototype).
ipcclient:
	$(CXX) $(IPCCLIENT_CXXFLAGS) -o $(IPCCLIENT) $(IPCCLIENT_SRC)

# Remove built binaries.
clean:
	rm -f $(TARGET) $(IPCCLIENT)

# Generate local CA and per-host TLS certificates (make certs HOST=mac-pro.local).
certs:
	sh $(CERTDIR)/Scripts/generate.sh $(HOST)
	@if [ ! -f $(CERTDIR)/passwordfile ]; then \
	  echo "NOTE: $(CERTDIR)/passwordfile missing."; \
	  echo "  Set Source/Config/Private/passwords.pl then: make passwordfile"; \
	fi

# Derive Certificates/passwordfile from Source/Config/Private/passwords.pl.
passwordfile:
	sh $(CERTDIR)/Scripts/digestpassword.sh

# Check TLS certificate expiry for all hosts.
certs-check:
	@sh $(CERTDIR)/Scripts/generate.sh --check

# Renew expired or expiring TLS certificates.
certs-renew:
	sh $(CERTDIR)/Scripts/generate.sh --renew
