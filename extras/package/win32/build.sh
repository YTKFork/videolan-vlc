#!/bin/sh

set -e
set -x

info()
{
    local green="\033[1;32m"
    local normal="\033[0m"
    echo "[${green}build${normal}] $1"
}

usage()
{
cat << EOF
usage: $0 [options]

Build vlc in the current directory

OPTIONS:
   -h            Show some help
   -r            Release mode (default is debug)
   -a <arch>     Use the specified arch (default: x86_64, possible i686, aarch64, armv7)
   -p            Use a Prebuilt contrib package (speeds up compilation)
   -c            Create a Prebuilt contrib package (rarely used)
   -l            Enable translations (can be slow)
   -i <n|r|u>    Create an Installer (n: nightly, r: release, u: unsigned release archive)
   -s            Interactive shell (get correct environment variables for build)
   -b <url>      Enable breakpad support and send crash reports to this URL
   -d            Create PDB files during the build
   -D <win_path> Create PDB files during the build, map the VLC sources to <win_path>
                 e.g.: -D c:/sources/vlc
   -x            Add extra checks when compiling
   -S <sdkver>   Use maximum Windows API version (0x0601000 by default)
   -u            Use the Universal C Runtime (instead of msvcrt)
   -w            Restrict to Windows Store APIs
   -z            Build without GUI (libvlc only)
   -o <path>     Install the built binaries in the absolute path
EOF
}

ARCH="x86_64"
while getopts "hra:pcli:sb:dD:xS:uwzo:" OPTION
do
     case $OPTION in
         r)
             RELEASE="yes"
             INSTALLER="r"
         ;;
         a)
             ARCH=$OPTARG
         ;;
         p)
             PREBUILT="yes"
         ;;
         c)
             PACKAGE="yes"
         ;;
         l)
             I18N="yes"
         ;;
         i)
             INSTALLER=$OPTARG
         ;;
         s)
             INTERACTIVE="yes"
         ;;
         b)
             BREAKPAD=$OPTARG
         ;;
         d)
             WITH_PDB="yes"
         ;;
         D)
             WITH_PDB="yes"
             PDB_MAP=$OPTARG
         ;;
         x)
             EXTRA_CHECKS="yes"
         ;;
         S)
             NTDDI=$OPTARG
         ;;
         u)
             BUILD_UCRT="yes"
         ;;
         w)
             WINSTORE="yes"
         ;;
         z)
             DISABLEGUI="yes"
         ;;
         o)
             INSTALL_PATH=$OPTARG
         ;;
         h|*)
             usage
             exit 1
         ;;
     esac
done
shift $(($OPTIND - 1))

if [ "x$1" != "x" ]; then
    usage
    exit 1
fi

case $ARCH in
    x86_64)
        SHORTARCH="win64"
        ;;
    i686)
        SHORTARCH="win32"
        ;;
    aarch64)
        SHORTARCH="winarm64"
        ;;
    armv7)
        SHORTARCH="winarm"
        ;;
    *)
        usage
        exit 1
esac

#####

SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
VLC_ROOT_PATH="$( cd "${SCRIPT_PATH}/../../.." ; pwd -P )"

JOBS=`getconf _NPROCESSORS_ONLN 2>&1`
TRIPLET=$ARCH-w64-mingw32

# Check if compiling with clang
CC=${CC:-$TRIPLET-gcc}
if ! printf "#ifdef __clang__\n#error CLANG\n#endif" | $CC -E - 1>/dev/null 2>/dev/null; then
    if ! printf "#if __clang_major__ >= 14\n#error CLANG\n#endif" | $CC -E - 1>/dev/null 2>/dev/null; then
        COMPILING_WITH_CLANG14=1
    fi
    COMPILING_WITH_CLANG=1
else
    COMPILING_WITH_CLANG=0
fi

# Check if this is a UCRT toolchain
if printf "#include <crtdefs.h>\n#if defined(_UCRT) || (__MSVCRT_VERSION__ >= 0x1400) || (__MSVCRT_VERSION__ >= 0xE00 && __MSVCRT_VERSION__ < 0x1000)\n# error This is a UCRT build\n#endif" | $CC -E - 1>/dev/null 2>/dev/null; then
    COMPILING_WITH_UCRT=0
else
    COMPILING_WITH_UCRT=1
fi

info "Building extra tools"
mkdir -p extras/tools
cd extras/tools
export VLC_TOOLS="$PWD/build"

export PATH="$PWD/build/bin":"$PATH"
# Force patched meson as newer versions don't add -lpthread properly in libplacebo.pc
FORCED_TOOLS="meson"
# Force libtool build when compiling with clang
if [ "$COMPILING_WITH_CLANG" -gt 0 ] && [ ! -d "libtool" ]; then
    FORCED_TOOLS="$FORCED_TOOLS libtool"
fi
# bootstrap only if needed in interactive mode
if [ "$INTERACTIVE" != "yes" ] || [ ! -f ./Makefile ]; then
    NEEDED="$FORCED_TOOLS" ${VLC_ROOT_PATH}/extras/tools/bootstrap
fi
make -j$JOBS

# avoid installing wine on WSL
# wine is needed to build Qt with shaders
if test -z "$(command -v wine)"
then
    if test -n "$(command -v wsl.exe)"
    then
        echo "Using wsl.exe to replace wine"
        echo "#!/bin/sh" > build/bin/wine
        echo "\"\$@\"" >> build/bin/wine
        chmod +x build/bin/wine
    fi
fi

cd ../../

CONTRIB_PREFIX=$TRIPLET
if [ -n "$BUILD_UCRT" ]; then

    if [ ! "$COMPILING_WITH_UCRT" -gt 0 ]; then
        echo "UCRT builds need a UCRT toolchain"
        exit 1
    fi

    if [ -n "$WINSTORE" ]; then
        CONTRIBFLAGS="$CONTRIBFLAGS --disable-disc --disable-srt --disable-sdl --disable-SDL_image --disable-caca"
        # modplug uses GlobalAlloc/Free and lstrcpyA/wsprintfA/lstrcpynA
        CONTRIBFLAGS="$CONTRIBFLAGS --disable-modplug"
        # x265 uses too many forbidden APIs
        CONTRIBFLAGS="$CONTRIBFLAGS --disable-x265"
        # aribb25 uses ANSI strings in WIDE APIs
        CONTRIBFLAGS="$CONTRIBFLAGS --disable-aribb25"
        # gettext uses sys/socket.h improperly
        CONTRIBFLAGS="$CONTRIBFLAGS --disable-gettext"
        # fontconfig uses GetWindowsDirectory and SHGetFolderPath
        CONTRIBFLAGS="$CONTRIBFLAGS --disable-fontconfig"
        # asdcplib uses some fordbidden SetErrorModes, GetModuleFileName in fileio.cpp
        CONTRIBFLAGS="$CONTRIBFLAGS --disable-asdcplib"
        # projectM is openGL based
        CONTRIBFLAGS="$CONTRIBFLAGS --disable-projectM"
        # gpg-error doesn't know minwg32uwp
        # CONTRIBFLAGS="$CONTRIBFLAGS --disable-gpg-error"
        # x264 build system claims it needs MSVC to build for WinRT
        CONTRIBFLAGS="$CONTRIBFLAGS --disable-x264"

        # libdsm is not enabled by default
        CONTRIBFLAGS="$CONTRIBFLAGS --enable-libdsm"

        CONTRIB_PREFIX="${CONTRIB_PREFIX}uwp"
    else
        CONTRIB_PREFIX="${CONTRIB_PREFIX}ucrt"
    fi
fi

export USE_FFMPEG=1
export PATH="$PWD/contrib/$CONTRIB_PREFIX/bin":"$PATH"

if [ "$INTERACTIVE" = "yes" ]; then
if [ "x$SHELL" != "x" ]; then
    exec $SHELL
else
    exec /bin/sh
fi
fi

VLC_CFLAGS="$CFLAGS"
unset CFLAGS
VLC_CXXFLAGS="$CXXFLAGS"
unset CXXFLAGS
VLC_CPPFLAGS="$CPPFLAGS"
unset CPPFLAGS
VLC_LDFLAGS="$LDFLAGS"
unset LDFLAGS

if [ -n "$BUILD_UCRT" ]; then
    WIDL=${TRIPLET}-widl
    VLC_CPPFLAGS="$VLC_CPPFLAGS -D__MSVCRT_VERSION__=0xE00 -D_UCRT"

    if [ -n "$WINSTORE" ]; then
        SHORTARCH="$SHORTARCH-uwp"
        TRIPLET=${TRIPLET}uwp
        VLC_CPPFLAGS="$VLC_CPPFLAGS -DWINAPI_FAMILY=WINAPI_FAMILY_APP -D_UNICODE -DUNICODE"

        if [ -z "$NTDDI" ]; then
            WINVER=0x0A00
        else
            WINVER=$(echo ${NTDDI} |cut -c 1-6)
            if [ "$WINVER" != "0x0A00" ]; then
                echo "Unsupported SDK/NTDDI version ${NTDDI} for Winstore"
            fi
        fi

        if [ "${COMPILING_WITH_CLANG14}" = "1" ]; then
            VLC_LDFLAGS="$VLC_LDFLAGS --start-no-unused-arguments"
            VLC_CFLAGS="$VLC_CFLAGS --start-no-unused-arguments"
            VLC_CXXFLAGS="$VLC_CXXFLAGS --start-no-unused-arguments"
        fi
        # WinstoreCompat: hopefully can go away someday
        VLC_LDFLAGS="$VLC_LDFLAGS -Wl,-lwindowsapp -Wl,-lwindowsappcompat"
        VLC_CFLAGS="$VLC_CFLAGS -Wl,-lwindowsapp,-lwindowsappcompat"
        VLC_CXXFLAGS="$VLC_CXXFLAGS -Wl,-lwindowsapp,-lwindowsappcompat"
        VLC_CPPFLAGS="$VLC_CPPFLAGS -DWINSTORECOMPAT"
        if [ "${COMPILING_WITH_CLANG14}" = "1" ]; then
            VLC_LDFLAGS="$VLC_LDFLAGS --end-no-unused-arguments"
            VLC_CFLAGS="$VLC_CFLAGS --end-no-unused-arguments"
            VLC_CXXFLAGS="$VLC_CXXFLAGS --end-no-unused-arguments"
        fi
    else
        SHORTARCH="$SHORTARCH-ucrt"
        WINVER=0x0601
    fi

    VLC_LDFLAGS="$VLC_LDFLAGS -lucrt"
    if [ ! "$COMPILING_WITH_CLANG" -gt 0 ]; then
        # assume gcc
        NEWSPECFILE="$(pwd)/specfile-$SHORTARCH"
        # tell gcc to replace msvcrt with ucrtbase+ucrt
        $CC -dumpspecs | sed -e "s/-lmsvcrt/-lucrt/" > $NEWSPECFILE
        VLC_CFLAGS="$VLC_CFLAGS -specs=$NEWSPECFILE"
        VLC_CXXFLAGS="$VLC_CXXFLAGS -specs=$NEWSPECFILE"

        if [ -n "$WINSTORE" ]; then
            # trick to provide these libraries instead of -ladvapi32 -lshell32 -luser32 -lkernel32
            sed -i -e "s/-ladvapi32/-lwindowsapp -lwindowsappcompat/" $NEWSPECFILE
            sed -i -e "s/-lshell32//" $NEWSPECFILE
            sed -i -e "s/-luser32//" $NEWSPECFILE
            sed -i -e "s/-lkernel32//" $NEWSPECFILE
        fi
    fi
else
    # use the regular msvcrt
    VLC_CPPFLAGS="$VLC_CPPFLAGS -D__MSVCRT_VERSION__=0x700"
fi

if [ -n "$NTDDI" ]; then
    WINVER=$(echo ${NTDDI} |cut -c 1-6)
    VLC_CPPFLAGS="$VLC_CPPFLAGS -DNTDDI_VERSION=$NTDDI"
fi
if [ -z "$WINVER" ]; then
    # The current minimum for VLC 3.0 is Windows XP SP1
    WINVER=0x0502
fi
VLC_CPPFLAGS="$VLC_CPPFLAGS -D_WIN32_WINNT=${WINVER} -DWINVER=${WINVER}"

VLC_CFLAGS="$VLC_CPPFLAGS $VLC_CFLAGS"
VLC_CXXFLAGS="$VLC_CPPFLAGS $VLC_CXXFLAGS"

info "Building contribs"
echo $PATH

mkdir -p contrib/contrib-$SHORTARCH && cd contrib/contrib-$SHORTARCH
if [ -n "$WITH_PDB" ]; then
    CONTRIBFLAGS="$CONTRIBFLAGS --enable-pdb"
    if [ "${COMPILING_WITH_CLANG14}" = "1" ]; then
        VLC_CFLAGS="$VLC_CFLAGS --start-no-unused-arguments"
        VLC_CXXFLAGS="$VLC_CXXFLAGS --start-no-unused-arguments"
        VLC_LDFLAGS="$VLC_LDFLAGS --start-no-unused-arguments"
    fi
    VLC_CFLAGS="$VLC_CFLAGS -g -gcodeview"
    VLC_CXXFLAGS="$VLC_CXXFLAGS -g -gcodeview"
    VLC_LDFLAGS="$VLC_LDFLAGS -Wl,-pdb="
    if [ -n "$PDB_MAP" ]; then
        VLC_CFLAGS="$VLC_CFLAGS -fdebug-prefix-map='$VLC_ROOT_PATH'='$PDB_MAP'"
        VLC_CXXFLAGS="$VLC_CXXFLAGS -fdebug-prefix-map='$VLC_ROOT_PATH'='$PDB_MAP'"
    fi
    if [ "${COMPILING_WITH_CLANG14}" = "1" ]; then
        VLC_CFLAGS="$VLC_CFLAGS --end-no-unused-arguments"
        VLC_CXXFLAGS="$VLC_CXXFLAGS --end-no-unused-arguments"
        VLC_LDFLAGS="$VLC_LDFLAGS --end-no-unused-arguments"
    fi
fi
if [ -n "$BREAKPAD" ]; then
     CONTRIBFLAGS="$CONTRIBFLAGS --enable-breakpad"
fi
if [ "$RELEASE" != "yes" ]; then
     CONTRIBFLAGS="$CONTRIBFLAGS --disable-optim"
fi
if [ -n "$DISABLEGUI" ]; then
    CONTRIBFLAGS="$CONTRIBFLAGS --disable-qt --disable-qtsvg --disable-qtdeclarative --disable-qtgraphicaleffects --disable-qtquickcontrols2"
fi

if [ "$COMPILING_WITH_CLANG" -gt 0 ]; then
    # avoid using gcc-ar with the clang toolchain, if both are installed
    VLC_AR="$TRIPLET-ar"
    # avoid using gcc-ranlib with the clang toolchain, if both are installed
    VLC_RANLIB="$TRIPLET-ranlib"
    # force linking with the static C++ runtime of LLVM
    if [ "${COMPILING_WITH_CLANG14}" = "1" ]; then
        VLC_CXXFLAGS="$VLC_CXXFLAGS --start-no-unused-arguments"
        VLC_LDFLAGS="$VLC_LDFLAGS --start-no-unused-arguments"
    fi
    VLC_LDFLAGS="$VLC_LDFLAGS -Wl,-l:libunwind.a -Wl,-l:libpthread.a -static-libstdc++"
    VLC_CXXFLAGS="$VLC_CXXFLAGS -Wl,-l:libunwind.a"
    if [ "${COMPILING_WITH_CLANG14}" = "1" ]; then
        VLC_CXXFLAGS="$VLC_CXXFLAGS --end-no-unused-arguments"
        VLC_LDFLAGS="$VLC_LDFLAGS --end-no-unused-arguments"
    fi
fi

if [ -z "$PKG_CONFIG" ]; then
    if [ "$(unset PKG_CONFIG_LIBDIR; $TRIPLET-pkg-config --version 1>/dev/null 2>/dev/null || echo FAIL)" = "FAIL" ]; then
        # $TRIPLET-pkg-config DOESNT WORK
        # on Debian it pretends it works to autoconf
        VLC_PKG_CONFIG="pkg-config"
        if [ -z "$PKG_CONFIG_LIBDIR" ]; then
            VLC_PKG_CONFIG_LIBDIR="/usr/$TRIPLET/lib/pkgconfig:/usr/lib/$TRIPLET/pkgconfig"
        else
            VLC_PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR:/usr/$TRIPLET/lib/pkgconfig:/usr/lib/$TRIPLET/pkgconfig"
        fi
    else
        VLC_PKG_CONFIG="$TRIPLET-pkg-config"
    fi
else
    VLC_PKG_CONFIG="$PKG_CONFIG"
fi

# generate the config.mak for contribs
test -e config.mak && unlink config.mak
exec 3>config.mak || return $?

printf '# This file was automatically generated!\n\n' >&3
if [ -n "$VLC_CPPFLAGS" ]; then
    printf '%s := %s\n' "CPPFLAGS" "${VLC_CPPFLAGS}" >&3
fi
if [ -n "$VLC_CFLAGS" ]; then
    printf '%s := %s\n' "CFLAGS" "${VLC_CFLAGS}" >&3
fi
if [ -n "$VLC_CXXFLAGS" ]; then
    printf '%s := %s\n' "CXXFLAGS" "${VLC_CXXFLAGS}" >&3
fi
if [ -n "$VLC_LDFLAGS" ]; then
    printf '%s := %s\n' "LDFLAGS" "${VLC_LDFLAGS}" >&3
fi
if [ -n "$VLC_AR" ]; then
    printf '%s := %s\n' "AR" "${VLC_AR}" >&3
fi
if [ -n "$VLC_RANLIB" ]; then
    printf '%s := %s\n' "RANLIB" "${VLC_RANLIB}" >&3
fi
if [ -n "$VLC_PKG_CONFIG" ]; then
    printf '%s := %s\n' "PKG_CONFIG" "${VLC_PKG_CONFIG}" >&3
fi
if [ -n "$VLC_PKG_CONFIG_LIBDIR" ]; then
    printf '%s := %s\n' "PKG_CONFIG_LIBDIR" "${VLC_PKG_CONFIG_LIBDIR}" >&3
fi


${VLC_ROOT_PATH}/contrib/bootstrap --host=$TRIPLET --prefix=../$CONTRIB_PREFIX $CONTRIBFLAGS

# Rebuild the contribs or use the prebuilt ones
if [ "$PREBUILT" = "yes" ]; then
    if [ -n "$VLC_PREBUILT_CONTRIBS_URL" ]; then
        make prebuilt PREBUILT_URL="$VLC_PREBUILT_CONTRIBS_URL" || PREBUILT_FAILED=yes
    else
        make prebuilt || PREBUILT_FAILED=yes
    fi
    make .luac
else
    PREBUILT_FAILED=yes
fi
make list
if [ -n "$PREBUILT_FAILED" ]; then
    make -j$JOBS fetch
    make -j$JOBS -k || make -j1
    if [ "$PACKAGE" = "yes" ]; then
        make package
    fi
else
    make .luac
fi
cd ../..

info "Bootstrapping"

${VLC_ROOT_PATH}/bootstrap

# set environment that will be kept in config.status
if [ -n "$VLC_CPPFLAGS" ]; then
    export CPPFLAGS="$VLC_CPPFLAGS"
fi
if [ -n "$VLC_CFLAGS" ]; then
    export CFLAGS="$VLC_CFLAGS"
fi
if [ -n "$VLC_CXXFLAGS" ]; then
    export CXXFLAGS="$VLC_CXXFLAGS"
fi
if [ -n "$VLC_LDFLAGS" ]; then
    export LDFLAGS="$VLC_LDFLAGS"
fi
if [ -n "$VLC_AR" ]; then
    export AR="$VLC_AR"
fi
if [ -n "$VLC_RANLIB" ]; then
    export RANLIB="$VLC_RANLIB"
fi
if [ -n "$VLC_PKG_CONFIG" ]; then
    export PKG_CONFIG="$VLC_PKG_CONFIG"
fi
if [ -n "$VLC_PKG_CONFIG_LIBDIR" ]; then
    export PKG_CONFIG_LIBDIR="$VLC_PKG_CONFIG_LIBDIR"
fi

info "Configuring VLC"

mkdir -p $SHORTARCH
cd $SHORTARCH

if [ "$RELEASE" != "yes" ]; then
     CONFIGFLAGS="$CONFIGFLAGS --enable-debug"
fi
if [ "$I18N" != "yes" ]; then
     CONFIGFLAGS="$CONFIGFLAGS --disable-nls"
fi
if [ -n "$BREAKPAD" ]; then
     CONFIGFLAGS="$CONFIGFLAGS --with-breakpad=$BREAKPAD"
fi
if [ -n "$WITH_PDB" ]; then
    CONFIGFLAGS="$CONFIGFLAGS --enable-pdb"
fi
if [ -n "$EXTRA_CHECKS" ]; then
    CFLAGS="$CFLAGS -Werror=incompatible-pointer-types -Werror=missing-field-initializers"
    CXXFLAGS="$CXXFLAGS -Werror=missing-field-initializers"
fi
if [ -n "$DISABLEGUI" ]; then
    CONFIGFLAGS="$CONFIGFLAGS --disable-vlc --disable-qt --disable-skins2"
else
    CONFIGFLAGS="$CONFIGFLAGS --enable-qt --enable-skins2"
fi
if [ -n "$WINSTORE" ]; then
    CONFIGFLAGS="$CONFIGFLAGS --enable-winstore-app"
    # uses CreateFile to access files/drives outside of the app
    CONFIGFLAGS="$CONFIGFLAGS --disable-vcd"
    # OpenGL is not supported in UWP
    CONFIGFLAGS="$CONFIGFLAGS --disable-gl"
    # other modules that were disabled in the old UWP builds
    CONFIGFLAGS="$CONFIGFLAGS --disable-crystalhd --disable-dxva2"

else
    CONFIGFLAGS="$CONFIGFLAGS --enable-dvdread --enable-caca"
fi
if [ -n "$INSTALL_PATH" ]; then
    CONFIGFLAGS="$CONFIGFLAGS --prefix=$INSTALL_PATH"
fi

${SCRIPT_PATH}/configure.sh --host=$TRIPLET --with-contrib=../contrib/$CONTRIB_PREFIX $CONFIGFLAGS

info "Compiling"
make -j$JOBS

if [ "$INSTALLER" = "n" ]; then
make package-win32-debug-7zip
make -j$JOBS package-win32 package-msi
elif [ "$INSTALLER" = "r" ]; then
make package-win32
elif [ "$INSTALLER" = "u" ]; then
make -j$JOBS package-win32-release package-win32-exe package-msi
sha512sum vlc-*-release.7z
sha512sum vlc-*-*.exe
sha512sum vlc-*-*.msi
elif [ -n "$INSTALL_PATH" ]; then
make package-win-install
fi
