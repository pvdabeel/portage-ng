# Copyright 2026 Pieter Van den Abeele
# Distributed under the terms of the GNU General Public License v2
# $Header$

EAPI="8"
DESCRIPTION="Description of test package foo"
HOMEPAGE="http://www.portage-ng.org/"
SRC_URI=""

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="alpha amd64 arm hppa ia64 m68k mips ppc ppc64 s390 sh sparc x86 sparc-fbsd x86-fbsd"
IUSE="+bar baz regular"
IUSE_RUNTIME="bar baz"

DEPEND=""
RDEPEND="bar? ( test82/bar ) baz? ( test82/baz ) regular? ( test82/reg )"

src_unpack() {
	echo "unpacking"
}

src_compile() {
	echo "compiling"
}

src_install() {
	echo "installing"
}
