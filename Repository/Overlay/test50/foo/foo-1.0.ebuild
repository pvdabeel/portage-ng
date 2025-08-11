# Copyright 2025 Pieter Van den Abeele
# Distributed under the terms of the GNU General Public License v2
# $Header$

EAPI="8"

DESCRIPTION="A build time dependency for app"
HOMEPAGE="https://www.portage-ng.org/"
SRC_URI=""

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="alpha amd64 arm hppa ia64 m68k mips ppc ppc64 s390 sh sparc x86 sparc-fbsd x86-fbsd"
IUSE=""

REQUIRED_USE=""

DEPEND=""
RDEPEND="test50/bar"

src_unpack() {
	echo "unpacking"
}

src_compile() {
	echo "compiling"
}

src_install() {
	echo "installing"
}
