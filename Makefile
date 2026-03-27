# Portage-ng makefile

## ----------------------------------------------------------------------
## You need to have a recent version of SWI-Prolog installed. Preferably 
## a development version (version 10.0.0 or higher). This Makefile will help
## you create a 'portage-ng' binary that can be installed in /usr/local
## The resulting binary can be passed several arguments (like --sync). 
## when --shell is passed, you are dumped into a shell allowing 
## you to query portage-ng and all its repositories directly. 
## the Makefile.
##
## See manpage for more information on how to use portage-ng.
## ----------------------------------------------------------------------


SUDO=sudo
TARGET=portage-ng

BUILDDIR=$(shell pwd)

help:     ## Show this help.
	  @sed -ne '/@sed/!s/## //p' $(MAKEFILE_LIST)

check:    ## Verify development environment (SWI-Prolog, shell aliases).
	  @ok=true; \
	  if ! command -v swipl >/dev/null 2>&1; then \
	    echo "ERROR: swipl not found in PATH."; \
	    echo "  Install SWI-Prolog >= 10.0.0: https://www.swi-prolog.org/download/devel"; \
	    ok=false; \
	  else \
	    echo "OK: swipl found ($$(swipl --version 2>&1 | head -1))"; \
	  fi; \
	  if ! command -v portage-ng-dev >/dev/null 2>&1; then \
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
	    echo "OK: portage-ng-dev found"; \
	  fi; \
	  if [ "$$ok" = false ]; then exit 1; fi

## all:      build & install
all:	  check build install 

build:	  ## Build the application.
	  swipl -O --stack_limit=32G -o $(TARGET)  -q -f portage-ng.pl -p portage=${BUILDDIR} -g main --stand_alone=true -c portage-ng.pl

install:  ## Install the application.
	  $(SUDO) cp $(TARGET) /usr/local/bin

test:     ## Run PLUnit tests.
	  ./Source/Application/System/Scripts/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
	load_files(portage('Source/Test/unittest'), [if(true)]).
	run_tests.
	halt.
	PL

test-overlay: ## Run overlay regression tests (requires loaded overlay repository).
	  ./Source/Application/System/Scripts/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
	test:run(cases).
	halt.
	PL

clean:    ## Remove the built binary.
	  rm -f $(TARGET)

CERTDIR=Certificates
HOST?=$(shell hostname)

certs:    ## Generate local CA + per-host client/server TLS certs (for --mode client/server). Usage: make certs HOST=mac-pro.local
	  sh $(CERTDIR)/Scripts/generate.sh $(HOST)

.PHONY: help check all build install test test-overlay clean certs
