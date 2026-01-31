# Copyright 2026 Pieter Van den Abeele
# Distributed under the terms of the GNU General Public License v2

EAPI="8"
DESCRIPTION="Cycle node A with bracket dep (test61)"
HOMEPAGE="http://www.portage-ng.org/"
SRC_URI=""

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="alpha amd64 arm hppa ia64 m68k mips ppc ppc64 s390 sh sparc x86 sparc-fbsd x86-fbsd"
IUSE="foo"

DEPEND="test61/b[foo]"
RDEPEND="test61/b[foo]"

src_unpack() { :; }
src_compile() { :; }
src_install() { :; }

