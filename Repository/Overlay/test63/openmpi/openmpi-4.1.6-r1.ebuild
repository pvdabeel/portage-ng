EAPI="8"

DESCRIPTION="Overlay test63: minimal openmpi REQUIRED_USE reproducer"
HOMEPAGE="http://www.portage-ng.org/"
SRC_URI=""

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="alpha amd64 arm hppa ia64 m68k mips ppc ppc64 s390 sh sparc x86 sparc-fbsd x86-fbsd"

# Intentionally default-enable the mutually exclusive flags to force work in
# REQUIRED_USE evaluation (mirrors the portage trace shape).
IUSE="+openmpi_rm_slurm +openmpi_rm_pbs openmpi_fabrics_ofed openmpi_ofed_features_control-hdr-padding openmpi_ofed_features_udcm openmpi_ofed_features_rdmacm openmpi_ofed_features_dynamic-sl"

REQUIRED_USE="
  openmpi_rm_slurm? ( !openmpi_rm_pbs )
  openmpi_rm_pbs? ( !openmpi_rm_slurm )

  openmpi_ofed_features_control-hdr-padding? ( openmpi_fabrics_ofed )
  openmpi_ofed_features_udcm? ( openmpi_fabrics_ofed )
  openmpi_ofed_features_rdmacm? ( openmpi_fabrics_ofed )
  openmpi_ofed_features_dynamic-sl? ( openmpi_fabrics_ofed )
"

DEPEND=""
RDEPEND=""
BDEPEND=""

src_unpack() { :; }
src_compile() { :; }
src_install() { :; }

