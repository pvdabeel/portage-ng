# Copyright 2026 Pieter Van den Abeele
# Distributed under the terms of the GNU General Public License v2

EAPI="8"
DESCRIPTION="App with versioned blocker (test60)"
HOMEPAGE="http://www.portage-ng.org/"
SRC_URI=""

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="alpha amd64 arm hppa ia64 m68k mips ppc ppc64 s390 sh sparc x86 sparc-fbsd x86-fbsd"
IUSE=""

DEPEND="test60/os"
RDEPEND="test60/os !<test60/windows-2.0"

src_unpack() { :; }
src_compile() { :; }
src_install() { :; }

