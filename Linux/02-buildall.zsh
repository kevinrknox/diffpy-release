#!/bin/zsh -f

setopt extendedglob
setopt err_exit
umask 022

DOC="\
${0:t} build all codes for the diffpy Linux bundle.
usage: ${0:t} [options] [FIRST] [LAST]

With no arguments all packages are built in sequence.  Otherwise the build
starts at package number FIRST and terminates after package LAST.
Use option --list for displaying package numbers.

Options:

  --list        show a numbered list of packages and exit
  -h, --help    display this message and exit

Environment variables can be used to override script defaults:

  PREFIX        base directory for installing the binaries [.]
  PYTHON        python executable used for the build [python]
  EASY_INSTALL  easy_install program used for the build [easy_install]
  SCONS         SCons program used for the build [scons]
  NCPU          number of CPUs used in parallel builds [all-cores].
"
DOC=${${DOC##[[:space:]]##}%%[[:space:]]##}
MYDIR="$(cd ${0:h} && pwd)"

# Parse Options --------------------------------------------------------------

zmodload zsh/zutil
zparseopts -K -E -D \
    h=opt_help -help=opt_help l=opt_list -list=opt_list

if [[ -n ${opt_help} ]]; then
    print -r -- $DOC
    exit
fi

integer FIRST=${1:-"1"}
integer LAST=${2:-"9999"}

# Resolve parameters that can be overloaded from the environment -------------

: ${PREFIX:=${MYDIR}}
: ${PYTHON:==python}
: ${EASY_INSTALL:==easy_install}
: ${SCONS:==scons}
: ${NCPU:=$(${PYTHON} -c \
    'from multiprocessing import cpu_count; print cpu_count()')}

# Determine other parameters -------------------------------------------------

SRCDIR=${MYDIR}/src
BINDIR=${PREFIX}/bin
INCLUDEDIR=${PREFIX}/include
LIBDIR=${PREFIX}/lib
PYTHON_VERSION=$($PYTHON -c 'import sys; print "%s.%s" % sys.version_info[:2]')
PYTHONDIR=$LIBDIR/python${PYTHON_VERSION}/site-packages
RELPATH=${MYDIR}/buildtools/relpath

# Adjust environment variables used in the build -----------------------------

export PATH=$BINDIR:$PATH
export LIBRARY_PATH=$LIBDIR:$LIBRARY_PATH
export LD_LIBRARY_PATH=$LIBDIR:$LD_LIBRARY_PATH
export CPATH=$INCLUDEDIR:$CPATH
export PYTHONPATH=$PYTHONDIR:$PYTHONPATH

# Define function for building or skipping the packages ----------------------

integer BIDX=0

ListSkipOrBuild() {
    local name=${1?}
    (( ++BIDX ))
    if [[ -n ${opt_list} ]]; then
        print $BIDX $name
        return 0
    fi
    if [[ $BIDX -lt $FIRST || $BIDX -gt $LAST ]]; then
        return 0
    fi
    local dashline="# $BIDX $name ${(l:80::-:):-}"
    print ${dashline[1,78]}
    # return false status to trigger the build section
    return 1
}

# Build commands here --------------------------------------------------------

if [[ -z ${opt_list} ]]; then
    mkdir -p $BINDIR $INCLUDEDIR $LIBDIR $PYTHONDIR
fi

cd $SRCDIR

ListSkipOrBuild pycifrw || {
    cd ${SRCDIR}/pycifrw/pycifrw
    make
    ${PYTHON} setup.py install --prefix=$PREFIX
}

ListSkipOrBuild diffpy.Structure || {
    $EASY_INSTALL -UZN --prefix=$PREFIX ${SRCDIR}/diffpy.Structure
}

ListSkipOrBuild diffpy.utils || {
    $EASY_INSTALL -UZN --prefix=$PREFIX ${SRCDIR}/diffpy.utils
}

ListSkipOrBuild periodictable || {
    $EASY_INSTALL -UZN --prefix=$PREFIX ${SRCDIR}/periodictable
}

ListSkipOrBuild cctbx || {
    mkdir -p ${SRCDIR}/cctbx/cctbx_build
    cctbx_configargs=(
        --no-bin-python
        # 2013-10-30 PJ:
        # cctbx Python extensions get linked to included boost_python, not
        # sure if it is possible to link with the system boost_python.
        # For now the build of extensions is disabled.
        --build-boost-python-extensions=False
        mmtbx libtbx cctbx iotbx fftw3tbx rstbx spotfinder
        smtbx mmtbx cbflib clipper
    )
    cd ${SRCDIR}/cctbx/cctbx_build
    $PYTHON ../cctbx_sources/libtbx/configure.py $cctbx_configargs
    ./bin/libtbx.scons -j $NCPU
    ( source setpaths.sh &&
      cd ../cctbx_sources/setup &&
      ./unix_integrate_cctbx.sh \
            --prefix=$PREFIX --yes pylibs libs includes
    )
}

ListSkipOrBuild patch_cctbx_pth || {
    CCTBXBDIR=${SRCDIR}/cctbx/cctbx_build
    cd $PYTHONDIR
    cctbxpth="$(<cctbx.pth)"
    lines=( ${(f)cctbxpth} )
    if [[ -n ${(M)lines:#/*} ]]; then
        lines[1]="import os; os.environ.setdefault('LIBTBX_BUILD', os.path.abspath(os.path.dirname(fullname) + '$($RELPATH $CCTBXBDIR .)'))"
        lines=( ${lines[1]} ${(f)"$($RELPATH ${lines[2,-1]} .)"} )
        print -l ${lines} >| cctbx.pth
    fi
}

ListSkipOrBuild cxxtest || {
    cd $BINDIR && ln -sf ../src/cxxtest/bin/cxxtestgen && ls -L cxxtestgen
}

ListSkipOrBuild libObjCryst || {
    cd $SRCDIR/pyobjcryst/libobjcryst
    $SCONS -j $NCPU build=fast with_shared_cctbx=yes prefix=$PREFIX install
}

ListSkipOrBuild pyobjcrst || {
    cd $SRCDIR/pyobjcryst
    $SCONS -j $NCPU build=fast prefix=$PREFIX install
}

ListSkipOrBuild libdiffpy || {
    cd $SRCDIR/libdiffpy
    $SCONS -j $NCPU build=fast enable_objcryst=yes test
    $SCONS -j $NCPU build=fast enable_objcryst=yes prefix=$PREFIX install
}

ListSkipOrBuild diffpy.srreal || {
    cd $SRCDIR/diffpy.srreal
    $SCONS -j $NCPU build=fast prefix=$PREFIX install
}

ListSkipOrBuild sans/data_util || {
    cd ${SRCDIR}/sans/data_util
    ${PYTHON} setup.py install --prefix=$PREFIX
}

ListSkipOrBuild sans/sansdataloader || {
    cd ${SRCDIR}/sans/sansdataloader
    ${PYTHON} setup.py install --prefix=$PREFIX
}

ListSkipOrBuild sans/sansmodels || {
    cd ${SRCDIR}/sans/sansmodels
    ${PYTHON} setup.py install --prefix=$PREFIX
}

ListSkipOrBuild sans/pr_inversion || {
    cd ${SRCDIR}/sans/pr_inversion
    ${PYTHON} setup.py install --prefix=$PREFIX
}

ListSkipOrBuild diffpy.srfit || {
    $EASY_INSTALL -UZN --prefix=$PREFIX ${SRCDIR}/diffpy.srfit
}

ListSkipOrBuild patch_so_rpath || {
    libsofiles=( $LIBDIR/*.so(*) )
    pyextfiles=(
        ${SRCDIR}/cctbx/cctbx_build/lib/*_ext.so(*N)
        ${LIBDIR}/python*/site-packages/**/*.so(*)
    )
    typeset -aU depdirs
    for f in $libsofiles $pyextfiles; do
        sodeps=( $(ldd $f | grep ${(F)libsofiles} | awk '$2 == "=>" {print $3}') )
        [[ ${#sodeps} != 0 ]] || continue
        depdirs=( $($RELPATH ${sodeps:h} ${f:h} ) )
        depdirs=( ${${(M)depdirs:#.}/*/'$ORIGIN'} '$ORIGIN'/${^${depdirs:#.}} )
        print "patchelf --set-rpath ${(j,:,)depdirs} $f"
        patchelf --set-rpath ${(j,:,)depdirs} $f
    done
}
