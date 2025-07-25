# Copyright 2025 Pieter Van den Abeele
# Distributed under the terms of the GNU General Public License v2
# $Header$

EAPI="8"

DESCRIPTION="Description of test package app"
HOMEPAGE="http://www.portage-ng.org/"
SRC_URI=""

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~*"
IUSE=""

DEPEND="test42/lib:*"
RDEPEND="${DEPEND}"

src_unpack() {
	echo "unpacking"
}

src_compile() {
	echo "compiling"
}

src_install() {
	echo "installing"
}