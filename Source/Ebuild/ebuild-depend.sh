#!/usr/bin/env bash
# ebuild-depend.sh — Standalone metadata extractor for Gentoo ebuilds
#
# Extracts dependency metadata (DEPEND, RDEPEND, SLOT, etc.) by sourcing
# ebuilds and their eclasses in the "depend" phase. Self-contained: does
# not require portage's ebuild.sh or its python stack.
#
# Three modes:
#
#   --single EBUILD REPO   Process one ebuild, output KEY=VALUE, exit.
#   --batch  REPO          Read ebuild descriptors from stdin, output
#                          KEY=VALUE blocks delimited by ---END---.
#   --server REPO          Persistent coprocess: read requests from stdin,
#                          output KEY=VALUE blocks delimited by ---END---.
#
# Copyright (c) 2026, Pieter Van den Abeele
#
# Copyright 1999-2025 Gentoo Authors
# Portions derived from Gentoo Portage: 
# (eapi.sh, ebuild.sh, isolated-functions.sh, version-functions.sh)
# 
# Distributed under the terms of the GNU General Public License v2

set -f

# =============================================================================
#  Section 1: EAPI feature detection (from portage eapi.sh)
# =============================================================================

___eapi_default_src_test_disables_parallel_jobs()                [[ ${1-${EAPI-0}} == [0-4] ]]
___eapi_has_S_WORKDIR_fallback()                                 [[ ${1-${EAPI-0}} == [0-3] ]]
___eapi_has_pkg_pretend()                                        [[ ${1-${EAPI-0}} != [0-3] ]]
___eapi_has_src_configure()                                      [[ ${1-${EAPI-0}} != [01]  ]]
___eapi_has_src_prepare()                                        [[ ${1-${EAPI-0}} != [01]  ]]

___eapi_has_BDEPEND()                                            [[ ${1-${EAPI-0}} != [0-6] ]]
___eapi_has_BROOT()                                              [[ ${1-${EAPI-0}} != [0-6] ]]
___eapi_has_IDEPEND()                                            [[ ${1-${EAPI-0}} != [0-7] ]]
___eapi_has_PORTDIR_ECLASSDIR()                                  [[ ${1-${EAPI-0}} == [0-6] ]]
___eapi_has_RDEPEND_DEPEND_fallback()                            [[ ${1-${EAPI-0}} == [0-3] ]]
___eapi_has_SYSROOT()                                            [[ ${1-${EAPI-0}} != [0-6] ]]
___eapi_has_accumulated_PROPERTIES()                             [[ ${1-${EAPI-0}} != [0-7] ]]
___eapi_has_accumulated_RESTRICT()                               [[ ${1-${EAPI-0}} != [0-7] ]]
___eapi_has_prefix_variables()                                   [[ ${1-${EAPI-0}} != [0-2] ]]

___eapi_has_assert()                                             [[ ${1-${EAPI-0}} == [0-8] ]]
___eapi_has_docompress()                                         [[ ${1-${EAPI-0}} != [0-3] ]]
___eapi_has_dohard()                                             [[ ${1-${EAPI-0}} == [0-3] ]]
___eapi_has_doheader()                                           [[ ${1-${EAPI-0}} != [0-4] ]]
___eapi_has_dohtml()                                             [[ ${1-${EAPI-0}} == [0-6] ]]
___eapi_has_dolib_libopts()                                      [[ ${1-${EAPI-0}} == [0-6] ]]
___eapi_has_domo()                                               [[ ${1-${EAPI-0}} == [0-8] ]]
___eapi_has_dosed()                                              [[ ${1-${EAPI-0}} == [0-3] ]]
___eapi_has_dostrip()                                            [[ ${1-${EAPI-0}} != [0-6] ]]
___eapi_has_eapply()                                             [[ ${1-${EAPI-0}} != [0-5] ]]
___eapi_has_eapply_user()                                        [[ ${1-${EAPI-0}} != [0-5] ]]
___eapi_has_edo()                                                [[ ${1-${EAPI-0}} != [0-8] ]]
___eapi_has_einstall()                                           [[ ${1-${EAPI-0}} == [0-5] ]]
___eapi_has_einstalldocs()                                       [[ ${1-${EAPI-0}} != [0-5] ]]
___eapi_has_get_libdir()                                         [[ ${1-${EAPI-0}} != [0-5] ]]
___eapi_has_hasq()                                               [[ ${1-${EAPI-0}} == [0-7] ]]
___eapi_has_hasv()                                               [[ ${1-${EAPI-0}} == [0-7] ]]
___eapi_has_in_iuse()                                            [[ ${1-${EAPI-0}} != [0-5] ]]
___eapi_has_nonfatal()                                           [[ ${1-${EAPI-0}} != [0-3] ]]
___eapi_has_pipestatus()                                         [[ ${1-${EAPI-0}} != [0-8] ]]
___eapi_has_useq()                                               [[ ${1-${EAPI-0}} == [0-7] ]]
___eapi_has_usex()                                               [[ ${1-${EAPI-0}} != [0-4] ]]
___eapi_has_ver_replacing()                                      [[ ${1-${EAPI-0}} != [0-8] ]]
___eapi_has_version_functions()                                  [[ ${1-${EAPI-0}} != [0-6] ]]

___eapi_best_version_and_has_version_support_--host-root()       [[ ${1-${EAPI-0}} == [56]  ]]
___eapi_best_version_and_has_version_support_-b_-d_-r()          [[ ${1-${EAPI-0}} != [0-6] ]]
___eapi_die_can_respect_nonfatal()                               [[ ${1-${EAPI-0}} != [0-5] ]]
___eapi_doconfd_respects_insopts()                               [[ ${1-${EAPI-0}} == [0-7] ]]
___eapi_dodoc_supports_-r()                                      [[ ${1-${EAPI-0}} != [0-3] ]]
___eapi_doenvd_respects_insopts()                                [[ ${1-${EAPI-0}} == [0-7] ]]
___eapi_doheader_respects_insopts()                              [[ ${1-${EAPI-0}} == [0-7] ]]
___eapi_doinitd_respects_exeopts()                               [[ ${1-${EAPI-0}} == [0-7] ]]
___eapi_doins_and_newins_preserve_symlinks()                     [[ ${1-${EAPI-0}} != [0-3] ]]
___eapi_domo_respects_into()                                     [[ ${1-${EAPI-0}} == [0-6] ]]
___eapi_econf_passes_--datarootdir()                             [[ ${1-${EAPI-0}} != [0-7] ]]
___eapi_econf_passes_--disable-dependency-tracking()             [[ ${1-${EAPI-0}} != [0-3] ]]
___eapi_econf_passes_--disable-silent-rules()                    [[ ${1-${EAPI-0}} != [0-4] ]]
___eapi_econf_passes_--disable-static()                          [[ ${1-${EAPI-0}} != [0-7] ]]
___eapi_econf_passes_--docdir_and_--htmldir()                    [[ ${1-${EAPI-0}} != [0-5] ]]
___eapi_econf_passes_--with-sysroot()                            [[ ${1-${EAPI-0}} != [0-6] ]]
___eapi_has_DESTTREE_INSDESTTREE()                               [[ ${1-${EAPI-0}} == [0-6] ]]
___eapi_has_dosym_r()                                            [[ ${1-${EAPI-0}} != [0-7] ]]
___eapi_helpers_can_die()                                        [[ ${1-${EAPI-0}} != [0-3] ]]
___eapi_newins_supports_reading_from_standard_input()            [[ ${1-${EAPI-0}} != [0-4] ]]
___eapi_unpack_is_case_sensitive()                               [[ ${1-${EAPI-0}} == [0-5] ]]
___eapi_unpack_supports_7z()                                     [[ ${1-${EAPI-0}} == [0-7] ]]
___eapi_unpack_supports_absolute_paths()                         [[ ${1-${EAPI-0}} != [0-5] ]]
___eapi_unpack_supports_lha()                                    [[ ${1-${EAPI-0}} == [0-7] ]]
___eapi_unpack_supports_rar()                                    [[ ${1-${EAPI-0}} == [0-7] ]]
___eapi_unpack_supports_txz()                                    [[ ${1-${EAPI-0}} != [0-5] ]]
___eapi_unpack_supports_xz()                                     [[ ${1-${EAPI-0}} != [0-2] ]]
___eapi_use_enable_and_use_with_support_empty_third_argument()   [[ ${1-${EAPI-0}} != [0-3] ]]
___eapi_usev_has_second_arg()                                    [[ ${1-${EAPI-0}} != [0-7] ]]

___eapi_bash_3_2()                                               [[ ${1-${EAPI-0}} == [0-5] ]]
___eapi_bash_4_2()                                               [[ ${1-${EAPI-0}} == [67]  ]]
___eapi_bash_5_0()                                               [[ ${1-${EAPI-0}} == 8     ]]
___eapi_bash_5_3()                                               [[ ${1-${EAPI-0}} != [0-8] ]]
___eapi_enables_failglob_in_global_scope()                       [[ ${1-${EAPI-0}} != [0-5] ]]
___eapi_has_ENV_UNSET()                                          [[ ${1-${EAPI-0}} != [0-6] ]]
___eapi_has_strict_keepdir()                                     [[ ${1-${EAPI-0}} != [0-7] ]]


# =============================================================================
#  Section 2: Utility functions (minimal from isolated-functions.sh)
# =============================================================================

die() {
	echo "die: $*" >&2
	exit 1
}

has() {
	local needle=$1; shift
	local x
	for x in "$@"; do
		[[ ${x} == "${needle}" ]] && return 0
	done
	return 1
}

contains_word() {
	local needle=$1; shift
	local haystack w
	for haystack in "$@"; do
		for w in ${haystack}; do
			[[ ${w} == "${needle}" ]] && return 0
		done
	done
	return 1
}

hasq() { has "$@"; }
hasv() {
	local needle=$1; shift
	local x
	for x in "$@"; do
		if [[ ${x} == "${needle}" ]]; then
			echo "${x}"
			return 0
		fi
	done
	return 1
}

assert() {
	local x pipestatus=( "${PIPESTATUS[@]}" )
	for x in "${pipestatus[@]}"; do
		[[ ${x} -eq 0 ]] || die "$@"
	done
}

nonfatal()                     { "$@"; }

einfo()                        { echo "$*" >&2; }
einfon()                       { echo -n "$*" >&2; }
ewarn()                        { echo "ewarn: $*" >&2; }
eerror()                       { echo "eerror: $*" >&2; }
eqawarn()                      { :; }
elog()                         { :; }
ebegin()                       { :; }
eend()                         { return "${1:-0}"; }

debug-print()                  { :; }
debug-print-function()         { :; }
debug-print-section()          { :; }


# =============================================================================
#  Section 3: Stub functions (no-ops for depend phase)
# =============================================================================

use()                          { return 1; }
useq()                         { return 1; }
usev()                         { return 1; }
use_with()                     { return 1; }
use_enable()                   { return 1; }
usex()                         { echo "${3-no}"; }

in_iuse()                      { return 1; }
get_libdir()                   { echo "lib"; }
diropts()                      { :; }
docompress()                   { :; }
dostrip()                      { :; }
exeopts()                      { :; }
insopts()                      { :; }
libopts()                      { :; }
best_version()                 { return 1; }
has_version()                  { return 1; }
portageq()                     { return 1; }
register_die_hook()            { :; }
register_success_hook()        { :; }

__strip_duplicate_slashes()    { :; }

KV_major()                     { :; }
KV_minor()                     { :; }
KV_micro()                     { :; }
KV_to_int()                    { :; }
get_KV()                       { :; }

tc-is-cross-compiler()         { return 1; }
tc-arch()                      { echo "${ARCH:-amd64}"; }
tc-arch-kernel()               { echo "x86"; }
tc-is-gcc()                    { return 0; }
tc-is-clang()                  { return 1; }
tc-export()                    { :; }
tc-getPKG_CONFIG()             { echo "pkg-config"; }
tc-getCC()                     { echo "${CC:-cc}"; }
tc-getCXX()                    { echo "${CXX:-c++}"; }
tc-getLD()                     { echo "${LD:-ld}"; }
tc-getAR()                     { echo "${AR:-ar}"; }
tc-getRANLIB()                 { echo "${RANLIB:-ranlib}"; }
tc-getNM()                     { echo "${NM:-nm}"; }
tc-getOBJCOPY()                { echo "${OBJCOPY:-objcopy}"; }
tc-getOBJDUMP()                { echo "${OBJDUMP:-objdump}"; }
tc-getSTRIP()                  { echo "${STRIP:-strip}"; }
tc-getBUILD_CC()               { echo "${BUILD_CC:-cc}"; }
tc-is-softfloat()              { return 1; }


# =============================================================================
#  Section 4: Version functions (from portage version-functions.sh)
# =============================================================================

__ver_parse_range() {
	local range=${1} max=${2}
	[[ ${range} == [0-9]* ]] || die "${FUNCNAME}: range must start with a number"
	start=${range%-*}
	[[ ${range} == *-* ]] && end=${range#*-} || end=${start}
	if [[ ${end} ]]; then
		[[ ${start} -le ${end} ]] || die "${FUNCNAME}: end of range must be >= start"
		[[ ${end} -le ${max} ]] || end=${max}
	else
		end=${max}
	fi
}

__ver_split() {
	local v=${1} LC_ALL=C
	comp=()
	local s c
	while [[ ${v} ]]; do
		s=${v%%[a-zA-Z0-9]*}
		v=${v:${#s}}
		[[ ${v} == [0-9]* ]] && c=${v%%[^0-9]*} || c=${v%%[^a-zA-Z]*}
		v=${v:${#c}}
		comp+=( "${s}" "${c}" )
	done
}

ver_cut() {
	local range=${1} v=${2:-${PV}} start end
	local -a comp
	__ver_split "${v}"
	local max=$((${#comp[@]}/2))
	__ver_parse_range "${range}" "${max}"
	local IFS=
	if [[ ${start} -gt 0 ]]; then
		start=$(( start*2 - 1 ))
	fi
	echo "${comp[*]:start:end*2-start}"
}

ver_rs() {
	local v
	(( ${#} & 1 )) && v=${@: -1} || v=${PV}
	local start end i
	local -a comp
	__ver_split "${v}"
	local max=$((${#comp[@]}/2 - 1))
	while [[ ${#} -ge 2 ]]; do
		__ver_parse_range "${1}" "${max}"
		for (( i = start*2; i <= end*2; i+=2 )); do
			[[ ${i} -eq 0 && -z ${comp[i]} ]] && continue
			comp[i]=${2}
		done
		shift 2
	done
	local IFS=
	echo "${comp[*]}"
}

__ver_compare_int() {
	local a=$1 b=$2 d=$(( ${#1}-${#2} ))
	if [[ ${d} -gt 0 ]]; then
		printf -v b "%0${d}d%s" 0 "${b}"
	elif [[ ${d} -lt 0 ]]; then
		printf -v a "%0$(( -d ))d%s" 0 "${a}"
	fi
	[[ ${a} > ${b} ]] && return 3
	[[ ${a} == "${b}" ]]
}

__ver_compare() {
	local va=${1} vb=${2} a an al as ar b bn bl bs br re LC_ALL=C
	re="^([0-9]+(\.[0-9]+)*)([a-z]?)((_(alpha|beta|pre|rc|p)[0-9]*)*)(-r[0-9]+)?$"
	[[ ${va} =~ ${re} ]] || die "${FUNCNAME}: invalid version: ${va}"
	an=${BASH_REMATCH[1]} al=${BASH_REMATCH[3]} as=${BASH_REMATCH[4]} ar=${BASH_REMATCH[7]}
	[[ ${vb} =~ ${re} ]] || die "${FUNCNAME}: invalid version: ${vb}"
	bn=${BASH_REMATCH[1]} bl=${BASH_REMATCH[3]} bs=${BASH_REMATCH[4]} br=${BASH_REMATCH[7]}
	__ver_compare_int "${an%%.*}" "${bn%%.*}" || return
	while [[ ${an} == *.* && ${bn} == *.* ]]; do
		an=${an#*.} bn=${bn#*.}
		a=${an%%.*} b=${bn%%.*}
		if [[ ${a} == 0* || ${b} == 0* ]]; then
			[[ ${a} =~ 0+$ ]] && a=${a%"${BASH_REMATCH[0]}"}
			[[ ${b} =~ 0+$ ]] && b=${b%"${BASH_REMATCH[0]}"}
			[[ ${a} > ${b} ]] && return 3
			[[ ${a} < ${b} ]] && return 1
		else
			__ver_compare_int "${a}" "${b}" || return
		fi
	done
	[[ ${an} == *.* ]] && return 3
	[[ ${bn} == *.* ]] && return 1
	[[ ${al} > ${bl} ]] && return 3
	[[ ${al} < ${bl} ]] && return 1
	as=${as#_}${as:+_} bs=${bs#_}${bs:+_}
	while [[ -n ${as} && -n ${bs} ]]; do
		a=${as%%_*} b=${bs%%_*}
		if [[ ${a%%[0-9]*} == "${b%%[0-9]*}" ]]; then
			__ver_compare_int "${a##*[a-z]}" "${b##*[a-z]}" || return
		else
			[[ ${a%%[0-9]*} == p ]] && return 3
			[[ ${b%%[0-9]*} == p ]] && return 1
			[[ ${a} > ${b} ]] && return 3 || return 1
		fi
		as=${as#*_} bs=${bs#*_}
	done
	if [[ -n ${as} ]]; then
		[[ ${as} == p[_0-9]* ]] && return 3 || return 1
	elif [[ -n ${bs} ]]; then
		[[ ${bs} == p[_0-9]* ]] && return 1 || return 3
	fi
	__ver_compare_int "${ar#-r}" "${br#-r}" || return
	return 2
}

ver_test() {
	local va op vb
	if [[ $# -eq 3 ]]; then
		va=${1}; shift
	else
		va=${PVR}
	fi
	[[ $# -eq 2 ]] || die "${FUNCNAME}: bad number of arguments"
	op=${1} vb=${2}
	case ${op} in
		-eq|-ne|-lt|-le|-gt|-ge) ;;
		*) die "${FUNCNAME}: invalid operator: ${op}" ;;
	esac
	__ver_compare "${va}" "${vb}"
	test $? "${op}" 2
}


# =============================================================================
#  Section 5: inherit() and EXPORT_FUNCTIONS()
# =============================================================================

declare -ix ECLASS_DEPTH=0

inherit() {
	ECLASS_DEPTH=$((ECLASS_DEPTH + 1))

	local -x ECLASS
	local __export_funcs_var
	local location potential_location repo_location x
	local B_IUSE B_REQUIRED_USE B_DEPEND B_RDEPEND B_PDEPEND
	local B_BDEPEND B_IDEPEND B_PROPERTIES B_RESTRICT

	while [[ "${1}" ]]; do
		location=""
		ECLASS="${1}"
		__export_funcs_var=__export_functions_${ECLASS_DEPTH}
		unset "${__export_funcs_var}"

		for repo_location in "${PORTAGE_ECLASS_LOCATIONS[@]}"; do
			potential_location="${repo_location}/eclass/${1}.eclass"
			if [[ -f ${potential_location} ]]; then
				location="${potential_location}"
				break
			fi
		done
		[[ -z ${location} ]] && die "${1}.eclass could not be found by inherit()"

		set -f

		unset B_IUSE B_REQUIRED_USE B_DEPEND B_RDEPEND B_PDEPEND
		unset B_BDEPEND B_IDEPEND B_PROPERTIES B_RESTRICT
		[[ -v IUSE         ]] && B_IUSE="${IUSE}"
		[[ -v REQUIRED_USE ]] && B_REQUIRED_USE="${REQUIRED_USE}"
		[[ -v DEPEND       ]] && B_DEPEND="${DEPEND}"
		[[ -v RDEPEND      ]] && B_RDEPEND="${RDEPEND}"
		[[ -v PDEPEND      ]] && B_PDEPEND="${PDEPEND}"
		[[ -v BDEPEND      ]] && B_BDEPEND="${BDEPEND}"
		[[ -v IDEPEND      ]] && B_IDEPEND="${IDEPEND}"
		unset IUSE REQUIRED_USE DEPEND RDEPEND PDEPEND BDEPEND IDEPEND

		if ___eapi_has_accumulated_PROPERTIES; then
			[[ -v PROPERTIES ]] && B_PROPERTIES=${PROPERTIES}
			unset PROPERTIES
		fi
		if ___eapi_has_accumulated_RESTRICT; then
			[[ -v RESTRICT ]] && B_RESTRICT=${RESTRICT}
			unset RESTRICT
		fi

		set +f

		source "${location}" || die "died sourcing ${location} in inherit()"

		set -f

		[[ -v IUSE         ]] && E_IUSE+="${E_IUSE:+ }${IUSE}"
		[[ -v REQUIRED_USE ]] && E_REQUIRED_USE+="${E_REQUIRED_USE:+ }${REQUIRED_USE}"
		[[ -v DEPEND       ]] && E_DEPEND+="${E_DEPEND:+ }${DEPEND}"
		[[ -v RDEPEND      ]] && E_RDEPEND+="${E_RDEPEND:+ }${RDEPEND}"
		[[ -v PDEPEND      ]] && E_PDEPEND+="${E_PDEPEND:+ }${PDEPEND}"
		[[ -v BDEPEND      ]] && E_BDEPEND+="${E_BDEPEND:+ }${BDEPEND}"
		[[ -v IDEPEND      ]] && E_IDEPEND+="${E_IDEPEND:+ }${IDEPEND}"

		[[ -v B_IUSE ]] && IUSE="${B_IUSE}" || unset IUSE
		[[ -v B_REQUIRED_USE ]] && REQUIRED_USE="${B_REQUIRED_USE}" || unset REQUIRED_USE
		[[ -v B_DEPEND ]] && DEPEND="${B_DEPEND}" || unset DEPEND
		[[ -v B_RDEPEND ]] && RDEPEND="${B_RDEPEND}" || unset RDEPEND
		[[ -v B_PDEPEND ]] && PDEPEND="${B_PDEPEND}" || unset PDEPEND
		[[ -v B_BDEPEND ]] && BDEPEND="${B_BDEPEND}" || unset BDEPEND
		[[ -v B_IDEPEND ]] && IDEPEND="${B_IDEPEND}" || unset IDEPEND

		if ___eapi_has_accumulated_PROPERTIES; then
			[[ -v PROPERTIES ]] && E_PROPERTIES+="${E_PROPERTIES:+ }${PROPERTIES}"
			[[ -v B_PROPERTIES ]] && PROPERTIES=${B_PROPERTIES} || unset PROPERTIES
		fi
		if ___eapi_has_accumulated_RESTRICT; then
			[[ -v RESTRICT ]] && E_RESTRICT+="${E_RESTRICT:+ }${RESTRICT}"
			[[ -v B_RESTRICT ]] && RESTRICT=${B_RESTRICT} || unset RESTRICT
		fi

		set +f

		if [[ -n ${!__export_funcs_var} ]]; then
			for x in ${!__export_funcs_var}; do
				declare -F "${ECLASS}_${x}" >/dev/null ||
					die "EXPORT_FUNCTIONS: ${ECLASS}_${x} is not defined"
				eval "$x() { ${ECLASS}_${x} \"\$@\" ; }" > /dev/null
			done
		fi
		unset "${__export_funcs_var}"

		if ! contains_word "$1" "${INHERITED}"; then
			INHERITED+=" $1"
		fi
		if [[ ${ECLASS_DEPTH} -eq 1 ]]; then
			PORTAGE_EXPLICIT_INHERIT+=" $1"
		fi

		shift
	done
	((--ECLASS_DEPTH))
	return 0
}


EXPORT_FUNCTIONS() {
	[[ -z "${ECLASS}" ]] && die "EXPORT_FUNCTIONS without a defined ECLASS"
	eval "${__export_funcs_var}+=\" $*\""
}


# =============================================================================
#  Section 6: __process_ebuild()
# =============================================================================

__process_ebuild() {
	# Expects: CATEGORY, P, PN, PV, PR, PVR, PF, EBUILD set in the caller
	# Expects: PORTAGE_ECLASS_LOCATIONS array set
	# Outputs: KEY=VALUE lines to stdout

	unset EAPI DEPEND RDEPEND PDEPEND BDEPEND IDEPEND SLOT SRC_URI RESTRICT
	unset HOMEPAGE LICENSE DESCRIPTION KEYWORDS IUSE REQUIRED_USE PROPERTIES
	unset INHERITED ECLASS E_IUSE E_REQUIRED_USE
	unset E_DEPEND E_RDEPEND E_PDEPEND E_BDEPEND E_IDEPEND
	unset E_PROPERTIES E_RESTRICT
	unset PORTAGE_EXPLICIT_INHERIT DEFINED_PHASES

	EBUILD_PHASE=depend

	if ___eapi_enables_failglob_in_global_scope; then
		shopt -s failglob
	fi

	source "${EBUILD}" || { echo "---ERROR--- failed to source ${EBUILD}" >&2; return 1; }

	if ___eapi_enables_failglob_in_global_scope; then
		shopt -u failglob
	fi

	[[ -v EAPI ]] || EAPI=0

	if ___eapi_has_RDEPEND_DEPEND_fallback; then
		RDEPEND=${RDEPEND-${DEPEND}}
	fi

	# Merge eclass accumulations
	IUSE+="${IUSE:+ }${E_IUSE}"
	DEPEND+="${DEPEND:+ }${E_DEPEND}"
	RDEPEND+="${RDEPEND:+ }${E_RDEPEND}"
	PDEPEND+="${PDEPEND:+ }${E_PDEPEND}"
	BDEPEND+="${BDEPEND:+ }${E_BDEPEND}"
	IDEPEND+="${IDEPEND:+ }${E_IDEPEND}"
	REQUIRED_USE+="${REQUIRED_USE:+ }${E_REQUIRED_USE}"

	if ___eapi_has_accumulated_PROPERTIES; then
		PROPERTIES+="${PROPERTIES:+ }${E_PROPERTIES}"
	fi
	if ___eapi_has_accumulated_RESTRICT; then
		RESTRICT+="${RESTRICT:+ }${E_RESTRICT}"
	fi

	# Compute DEFINED_PHASES
	local _valid_phases _f
	case ${EAPI} in
		0|1) _valid_phases="src_compile pkg_config pkg_info src_install
			pkg_nofetch pkg_postinst pkg_postrm pkg_preinst pkg_prerm
			pkg_setup src_test src_unpack" ;;
		2|3) _valid_phases="src_compile pkg_config src_configure pkg_info
			src_install pkg_nofetch pkg_postinst pkg_postrm pkg_preinst
			src_prepare pkg_prerm pkg_setup src_test src_unpack" ;;
		*)   _valid_phases="src_compile pkg_config src_configure pkg_info
			src_install pkg_nofetch pkg_postinst pkg_postrm pkg_preinst
			src_prepare pkg_prerm pkg_pretend pkg_setup src_test src_unpack" ;;
	esac

	DEFINED_PHASES=
	for _f in ${_valid_phases}; do
		if declare -F "${_f}" >/dev/null; then
			_f=${_f#pkg_}
			DEFINED_PHASES+=" ${_f#src_}"
		fi
	done
	[[ -n ${DEFINED_PHASES} ]] || DEFINED_PHASES=-

	if ! ___eapi_has_BDEPEND; then
		unset BDEPEND
	fi
	if ! ___eapi_has_IDEPEND; then
		unset IDEPEND
	fi

	local INHERIT=${PORTAGE_EXPLICIT_INHERIT}

	# Output metadata (printf avoids subshell forks that $(echo ...) would cause)
	local _metadata_keys=(
		DEPEND RDEPEND SLOT SRC_URI RESTRICT HOMEPAGE LICENSE
		DESCRIPTION KEYWORDS INHERITED IUSE REQUIRED_USE PDEPEND BDEPEND
		EAPI PROPERTIES DEFINED_PHASES IDEPEND INHERIT
	)
	local _key _val
	for _key in "${_metadata_keys[@]}"; do
		_val="${!_key}"
		# Collapse newlines to spaces (matching ebuild.sh's $(echo ${!f}) behavior)
		_val="${_val//$'\n'/ }"
		# Collapse multiple spaces
		read -ra _parts <<< "${_val}"
		_val="${_parts[*]}"
		printf '%s=%s\n' "${_key}" "${_val}"
	done
}


# =============================================================================
#  Section 7: Mode dispatch
# =============================================================================

__mode_single() {
	local ebuild_path="$1"
	local repo_location="$2"

	[[ -f "${ebuild_path}" ]] || die "--single: ebuild not found: ${ebuild_path}"
	[[ -d "${repo_location}" ]] || die "--single: repo not found: ${repo_location}"

	PORTAGE_ECLASS_LOCATIONS=( "${repo_location}" )

	# Derive CATEGORY, PN, PV, etc. from the ebuild path
	# Path format: .../CATEGORY/PN/PF.ebuild
	local ebuild_file="${ebuild_path##*/}"
	local pf="${ebuild_file%.ebuild}"
	local pn_dir="${ebuild_path%/*}"
	local pn="${pn_dir##*/}"
	local cat_dir="${pn_dir%/*}"
	local category="${cat_dir##*/}"

	export CATEGORY="${CATEGORY:-${category}}"
	export PF="${PF:-${pf}}"
	export PN="${PN:-${pn}}"
	export EBUILD="${ebuild_path}"

	# Parse PV, PR, PVR from PF and PN
	local pvr="${PF#${PN}-}"
	if [[ ${pvr} == *-r[0-9]* ]]; then
		export PR="${PR:-${pvr##*-}}"
		export PV="${PV:-${pvr%-${PR}}}"
	else
		export PR="${PR:-r0}"
		export PV="${PV:-${pvr}}"
	fi
	export PVR="${PVR:-${pvr}}"
	export P="${P:-${PN}-${PV}}"

	(
		__process_ebuild
	)
}

__mode_batch() {
	local repo_location="$1"

	[[ -d "${repo_location}" ]] || die "--batch: repo not found: ${repo_location}"

	PORTAGE_ECLASS_LOCATIONS=( "${repo_location}" )

	local line
	while IFS= read -r line; do
		[[ -z "${line}" ]] && continue

		# Parse descriptor: space-separated KEY=VALUE pairs
		# Required: CATEGORY, PN, PV, PF, P, EBUILD
		# Optional: PR, PVR
		(
			eval "${line}" 2>/dev/null

			if [[ -z "${EBUILD}" ]]; then
				echo "---ERROR--- missing EBUILD in descriptor: ${line}"
				echo "---END---"
				return
			fi

			if [[ ! -f "${EBUILD}" ]]; then
				echo "---ERROR--- ebuild not found: ${EBUILD}"
				echo "---END---"
				return
			fi

			[[ -z "${PR}" ]] && PR=r0
			[[ -z "${PVR}" ]] && PVR="${PV}${PR:+-${PR}}"
			[[ "${PR}" == "r0" ]] && PVR="${PV}"

			export CATEGORY P PN PV PR PVR PF EBUILD

			__process_ebuild
			echo "---END---"
		)
	done
}

__mode_server() {
	local repo_location="$1"

	[[ -d "${repo_location}" ]] || die "--server: repo not found: ${repo_location}"

	PORTAGE_ECLASS_LOCATIONS=( "${repo_location}" )

	local line
	while IFS= read -r line; do
		[[ -z "${line}" ]] && continue
		[[ "${line}" == "QUIT" ]] && break

		(
			eval "${line}" 2>/dev/null

			if [[ -z "${EBUILD}" || ! -f "${EBUILD}" ]]; then
				echo "---ERROR--- invalid or missing EBUILD: ${EBUILD:-<empty>}"
				echo "---END---"
				return
			fi

			[[ -z "${PR}" ]] && PR=r0
			[[ -z "${PVR}" ]] && PVR="${PV}${PR:+-${PR}}"
			[[ "${PR}" == "r0" ]] && PVR="${PV}"

			export CATEGORY P PN PV PR PVR PF EBUILD

			__process_ebuild
			echo "---END---"
		)
	done
}


# =============================================================================
#  Section 8: Main
# =============================================================================

case "${1:-}" in
	--single)
		[[ $# -ge 3 ]] || die "Usage: ebuild-depend.sh --single EBUILD REPO"
		__mode_single "$2" "$3"
		;;
	--batch)
		[[ $# -ge 2 ]] || die "Usage: ebuild-depend.sh --batch REPO < ebuild-list"
		__mode_batch "$2"
		;;
	--server)
		[[ $# -ge 2 ]] || die "Usage: ebuild-depend.sh --server REPO"
		__mode_server "$2"
		;;
	*)
		echo "Usage: ebuild-depend.sh {--single EBUILD REPO | --batch REPO | --server REPO}" >&2
		exit 1
		;;
esac