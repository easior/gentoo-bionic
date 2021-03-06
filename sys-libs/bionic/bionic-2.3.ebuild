# FIXME: patches for USE=android vs USE=-android

EAPI=2

inherit eutils toolchain-funcs git

DESCRIPTION="The bionic C library"
HOMEPAGE="http://android.git.kernel.org/?p=platform/bionic.git"

LICENSE="BSD"
#KEYWORDS="~amd64 ~arm ~mips ~sh ~x86"
KEYWORDS="x86"

IUSE="debug cxx crosscompile_opts_headers-only"

export CBUILD=${CBUILD:-${CHOST}}
export CTARGET=${CTARGET:-${CHOST}}
if [[ ${CTARGET} == ${CHOST} ]] ; then
	if [[ ${CATEGORY/cross-} != ${CATEGORY} ]] ; then
		export CTARGET=${CATEGORY/cross-}
	fi
else
RESTRICT="strip"
fi

is_crosscompile() {
	[[ ${CHOST} != ${CTARGET} ]]
}

RDEPEND=""
PROVIDE="elibc_bionic? ( virtual/libc )"
if is_crosscompile; then
        DEPEND=""
        SLOT="${CTARGET}"
else
        DEPEND="virtual/os-headers"
        SLOT="0"
fi
DEPEND="${DEPEND} dev-lang/python"

bionic_arch() {
	local ctarget
	if is_crosscompile; then
		ctarget="${CTARGET}"
	else
		ctarget=${CHOST}
	fi
	case "${ctarget}" in
		*86*|amd64*|x86_64*) echo "x86";;
		arm*) echo "arm";;
		mips*) echo "mips";;
		sh*) echo "sh";;
		ppc*|powerpc*) echo "ppc";;
		*) ;;
	esac
}

bionic_arch_variant() {
	local ctarget
	if is_crosscompile; then
		ctarget="${CTARGET}"
	else
		ctarget=${CHOST}
	fi
	case "${ctarget}" in
		x86|i*86) echo "x86";;
		x86_64|amd64) echo "x86_64";;
# TODO: please fixme
#
#		arm*) echo "arm";;
#		mips*) echo "mips";;
#		sh*) echo "sh";;
#		ppc*|powerpc*) echo "ppc";;
		*) ;;
	esac
}

bionic_fenv_arch() {
	local ctarget
	if is_crosscompile; then
		ctarget="${CTARGET}"
	else
		ctarget=${CHOST}
	fi
	case "${ctarget}" in
		alpha*) echo "alpha";;
		amd64*|x64*) echo "amd64";;
		arm*) echo "arm";;
		ia64*) echo "ia64";;
		*86*) echo "i387";;
		mips*) echo "mips";;
		ppc*|ppc-*) echo "powerpc";;
		sh*) echo "sh";;
		sparc64*) echo "sparc64";;
		*) ;;
	esac
}

# Bionic uses a git repo. Tags have versions, but the numbering is not 
# compatible with Gentoo's version numbering system.
# Instead, I'm just going to use the 'official' Android release versions
# e.g. 2.3 <=> gingerbread-release <=> \
#      commit 2081fda69a68505c914324797400b1b798516904
#  
# and add -r# for gentoo ebuild revisions and / or bugfixes.

S="${WORKDIR}"/TinyAndroid

EGIT_BOOTSTRAP=1

src_unpack() {
	# FIXME: Probably could use git-submodule to make a small build tree
	# ${S}/TinyAndroid/{build,bionic}

	local patches=""

	# fetch the bionic sources
	EGIT_PROJECT=${PN}/${PN}
	EGIT_COMMIT="2081fda69a68505c914324797400b1b798516904"
#	EGIT_REPO_URI="git://android.git.kernel.org/platform/${PN}.git"
	EGIT_REPO_URI="https://android.googlesource.com/platform/${PN}.git"
	S="${S}"/${PN} \
		git_fetch

	# git.eclass patching is currently FUBAR
	cd "${S}"/${PN}
	patches="$(ls "${FILESDIR}"/bionic*.patch 2>/dev/null | sort -u)"
	if [ "${patches}" != "" ]; then
		for p in ${patches}; do
			EPATCH_OPTS="-p1" epatch ${p}
		done
	fi
	if use debug; then
		epatch "${FILESDIR}"/debug-bionic-libc.patch
	fi
	cp "${FILESDIR}"/AndroidConfig/$(bionic_arch).h libc/arch-$(bionic_arch)/AndroidConfig.h
	mkdir -p libc/include/private
	cp "${FILESDIR}"/android_filesystem_config.h libc/include/private

	# fetch the build system
	EGIT_PROJECT=${PN}/build
	EGIT_COMMIT="6f7a6ac0e92c0b33070adac84b714cbd67929c96"
	EGIT_REPO_URI="https://android.googlesource.com/platform/build.git"
	S="${S}"/build \
		git_fetch

	# git.eclass patching is currently FUBAR
	cd "${S}"/build
	patches="$(ls "${FILESDIR}"/build*.patch 2>/dev/null | sort -u)"
	if [ "${patches}" != "" ]; then
		for p in ${patches}; do
			EPATCH_OPTS="-p1" epatch ${p}
		done
	fi
}

src_prepare() {
	echo "include build/core/main.mk" > Makefile

	python bionic/libc/tools/gensyscalls.py || die
}

src_configure() {

	local cc
	if is_crosscompile; then
		cc=${CTARGET}-
	else
		cc=${CHOST}-
	fi
	local arch="$(bionic_arch)"
	local archv="$(bionic_arch_variant)"

	local headers=""
	local nocxx=""

	if use cxx; then
		nocxx="false";
	else
		for i in x86 arm; do
			sed -i \
				-e 's/libc\ libstdc++\ libm/libc\ libm/' \
				-e 's/g++/gcc/' \
				build/core/combo/TARGET_linux-${i}.mk
		done
	fi
	
	if use crosscompile_opts_headers-only; then
		headers=true;
	fi

	local debug="false";
	if use debug; then
		debug="true"
	fi

	einfo "CBUILD:                ${CBUILD}"
	einfo "CHOST:                 ${CHOST}"
	einfo "CTARGET:               ${CTARGET}"
	einfo "TARGET_ARCH:           ${arch}"
	einfo "TARGET_ARCH_VARIANT:   ${archv}"
	einfo "TARGET_TOOLS_PREFIX:   ${cc}"
	einfo "TARGET_NOCXX:          ${nocxx}"
	einfo "TARGET_HEADERS_ONLY:   ${headers}"
	einfo "DEBUG:                 ${debug}"

	# create an appropriate buildspec.mk
	local bs="${S}/buildspec.mk"
	echo "TARGET_NO_KERNEL := true"        >  ${bs}
	echo "TARGET_ARCH := ${arch}"          >> ${bs}
	echo "TARGET_ARCH_VARIANT := ${archv}" >> ${bs}
	echo "TARGET_TOOLS_PREFIX := ${cc}"    >> ${bs}
	if use cxx; then 
		echo "TARGET_NOCXX := false"    >> ${bs}
	fi
	if use debug; then
		echo "DEBUG_BIONIC_LIBC := true" >> ${bs}
	fi
}

ODIR="out/target/product/generic"
SYSRT="${ODIR}/system"
PTH="/usr/share/zoneinfo"
TZTARGETS="
	${SYSRT}${PTH}/zoneinfo.dat 
	${SYSRT}${PTH}/zoneinfo.idx 
	${SYSRT}${PTH}/zoneinfo.version"
CRTTARGETS="
	${ODIR}/obj/lib/crtbegin_dynamic.o
	${ODIR}/obj/lib/crtbegin_so.o 
	${ODIR}/obj/lib/crtbegin_static.o
	${ODIR}/obj/lib/crtend_android.o
	${ODIR}/obj/lib/crtend_so.o"
# These are not prefixed with a path in Android's build system
LIBTARGETS="libdl libc libm libthread_db"
BINTARGETS="linker"

src_compile() {
	local libtargets=${LIBTARGETS}
	if use cxx; then
		libtargets="${libtargets} libstdc++"
	fi
	if ! use crosscompile_opts_headers-only; then
		emake ${libtargets} ${BINTARGETS} ${TZTARGETS} ${CRTTARGETS} \
			|| die
	fi
}

do_headers_install() {
	local ic
	local arch="$(bionic_arch)"
	local farch="$(bionic_fenv_arch)"

	[[ -z ${farch} ]] && die "unknown floating-point arch"

	is_crosscompile && ic=/usr/${CTARGET}/usr/include || ic=/usr/include

	#
	# FIXME: 
	# bionic endian headers are not properly organized for installation
	#
	# My Solution:
	# /usr/include/endian.h will included <sys/endian.h>
	# <sys/endian.h> will pull-in <machine/endian.h>
	# ${S}/bionic/libc/arch-${arch}/endian.h will be inserted into
	# /usr/include/machine rather than /usr/include

	insinto ${ic}

	# install arch-independent libc headers
	cd "${S}"/bionic/libc/include
	doins -r * || die
	
	# install arch-specific libc headers
	cd "${S}"/bionic/libc/arch-${arch}/include
	doins -r machine || die

	insinto ${ic}/machine
	doins endian.h || die

	local f="${S}"/bionic/libc/include/sys/endian.h
	local W="${WORKDIR}"

	cd "${W}" || die
	cp "${f}" "${W}" || die
	patch -p0 < "${FILESDIR}"/sys-endian-include-machine-endian.patch || die

	insinto ${ic}/sys
	doins endian.h || die
	insinto ${ic}

	cd "${S}"/bionic/libm/include
	doins math.h ${farch}/fenv.h || die

	cd "${S}"/bionic/libc/private
	insinto ${ic}/private
	doins resolv_private.h resolv_static.h arpa_nameser.h arpa_nameser_compat.h || die

# FIXME: insert C++ headers
	insinto ${ic}/c++/4.5
	cd "${S}"/bionic/libstdc++/include
        doins * || die
}

src_install() {
	if ! use crosscompile_opts_headers-only; then

		local pfx
		is_crosscompile && pfx="/usr/${CTARGET}" || pfx=""

		local libtargets=${LIBTARGETS}
		if use cxx; then
			libtargets="${libtargets} libstdc++"
		fi

		# dobin inserts into /usr/bin rather than bin
		insinto ${pfx}/bin
		for b in ${BINTARGETS}; do
			doins ${SYSRT}/bin/${b} || die
			chmod +x "${D}"/${pfx}/bin/${b} || die
		done
		
		local libtargets=${LIBTARGETS}
		if use cxx; then
			libtargets="${libtargets} libstdc++"
		fi

		# on x86_64 targets, dolib will insert into /lib64
		insinto ${pfx}/lib
		for l in ${libtargets}; do
			doins ${SYSRT}/../obj/lib/${l}.so || die
		done

		insinto ${pfx}/usr/share/zoneinfo
		for z in ${TZTARGETS}; do 
			doins ${z} || die
		done

		insinto ${pfx}/usr/lib

		for l in ${CRTTARGETS}; do 
			doins ${l} || die
		done

		local atargets="c m thread_db"
		if use cxx; then
			atargets="${atargets} stdc++"
		fi
		local blah
		for l in ${atargets}; do
			blah=STATIC_LIBRARIES/lib${l}_intermediates/lib${l}.a 
			doins ${SYSRT}/../obj/${blah} || die
		done
	fi

	do_headers_install
}
