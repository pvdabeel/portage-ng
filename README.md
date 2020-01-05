Automate building and maintaining custom operating systems using declarative reasoning.

# Prolog code 

This repository contains Prolog code:

- [context](Source/context.pl): An implementation of a Contextual Object Oriented Logic Programming paradigm for SWI-Prolog,
- [eapi](Source/eapi.pl): A DCG Grammar for reading EAPI-7 (or earlier) compliant Gentoo ebuild information into Prolog facts and rules,
- [knowledgebase](Source/knowledgebase.pl): A structure to which Gentoo overlays and repositories can be registered. 
- [repository](Source/repository.pl): A Prolog class representing a Gentoo Portage repository. Offers datalog-style querying and Git, Rsync or Webrsync syncing.

Other interesting files: 
- An ebuild [reader](Source/reader.pl) & [parser](Source/parser.pl), 
- A [prover](Source/prover.pl) which uses declarative reasoning to compute a Model and a logic Proof for realisation of a given ebuild,
- A [planner](Source/planner.pl) capable of creating a build plan (Makefile) for realisation of a given ebuid proof,
- A pretty [printer](Source/printer.pl) for build plans,
- A [grapher](Source/grapher.pl) capable of creating graphviz DOT files and interactive SVG files,
- Domain-specific [rules](Source/rules.pl) for reasoning about ebuilds and their possible configurations, 

This repository also contains some bash [scripts](.bash_profile) to emulate Gentoo emerge.

## Some examples: 

## Portage SVG Graphs

The code is able to automatically generate interactive SVG graphs for all ebuilds, allowing you to walk
through the Ebuild dependency graph. Dot files and corresponding SVG can be found [here](https://www.github.com/pvdabeel/portage-svg)

![Portage SVG Graphs](https://i.imgur.com/WhuEGxx.png)


## Contextual logic programming 

The following screenshot shows a simple 'Person' class being instantiated. Private data member can be set and retrieved, but not accessed 
directly. 

The class code:

![Imgur](https://i.imgur.com/MRZwVUS.png)

The instance:

![Imgur](https://i.imgur.com/O7Luag9.png)


## Syncing repositories

The following screenshot shows a Gentoo Portage repository and a Gentoo overlay being synced using git. Only the changed ebuilds have their 
Logic metadata updated. 

![Imgur](https://i.imgur.com/HNp6QYD.png)


## Reading, parsing & querying ebuilds 

In the following screenshots we show Gentoo ebuilds being read, parsed and queried using Prolog

![Imgur](https://i.imgur.com/jHNSVdl.png)

![Imgur](https://i.imgur.com/oGplVXX.png)

![Imgur](https://i.imgur.com/wWAdjXn.png)

![Imgur](https://i.imgur.com/yVED5fZ.png)


## Installation instructions: 

Not available at this time.
