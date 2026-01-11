# Portage-ng makefile

## ----------------------------------------------------------------------
## You need to have a recent version of SWI-Prolog installed. Preferably 
## a development version (version 9.3 or higher). This Makefile will help
## you create a 'portage-ng' binary that can be installed in /usr/local
## The resulting binary can be passed several arguments (like --sync). 
## When no arguments are supplied, you are dumped into a shell allowing 
## you to query portage-ng and all its repositories directly. 
## the Makefile.
## ----------------------------------------------------------------------


SUDO=sudo
TARGET=portage-ng

BUILDDIR=$(shell pwd)

help:     ## Show this help.
	  @sed -ne '/@sed/!s/## //p' $(MAKEFILE_LIST)

## all:      build & install
all:	  build install 

build:	  ## Build the application.
	  swipl --stack_limit=32G -o $(TARGET) -O -q -f portage-ng.pl -p portage=${BUILDDIR} -g main --stand_alone=true -c portage-ng.pl

install:  ## Install the application.
	  $(SUDO) cp $(TARGET) /usr/local/bin

CERTDIR=Source/Certificates
HOST?=$(shell hostname)

certs:    ## Generate local CA + per-host client/server TLS certs (for --mode client/server). Usage: make certs HOST=mac-pro.local
	  sh $(CERTDIR)/generate.sh $(HOST)
