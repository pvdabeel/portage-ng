#+#+#+#+#######################################################################
# Overlay test63
#
# Keep the ebuild format aligned with the existing overlay tests so that
# the cache generator (md5-cache) reliably extracts DEPEND/RDEPEND/REQUIRED_USE.
#+#+#+#+#######################################################################

EAPI="8"

DESCRIPTION="Overlay test63 root package"
HOMEPAGE="http://www.portage-ng.org/"
SRC_URI=""

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="alpha amd64 arm hppa ia64 m68k mips ppc ppc64 s390 sh sparc x86 sparc-fbsd x86-fbsd"
IUSE=""

DEPEND=""
RDEPEND="test63/mpibash"

src_unpack() { :; }
src_compile() { :; }
src_install() { :; }

