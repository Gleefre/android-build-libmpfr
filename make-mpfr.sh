#!/bin/sh
set -e

# Download source
version=4.2.2
ext=tar.xz
if [ ! -f mpfr-$version.$ext ]; then
    wget https://www.mpfr.org/mpfr-$version/mpfr-$version.$ext
fi
# Clean old folders if they exist
rm -rf mpfr
rm -rf mpfr-$version
# Unpack
tar -xf mpfr-$version.$ext
mv mpfr-$version mpfr

# Configure NDK.

if [ -z $NDK ]; then
    echo "Please set NDK path variable." && exit 1
fi

if [ -z $ABI ]; then
    echo "Running adb to determine target ABI..."
    ABI=`adb shell uname -m`
    echo $ABI
fi
case $ABI in
    arm64-v8a) TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7a-linux-androideabi ;;
    x86) TARGET=i686-linux-android ;;
    x86_64) TARGET=x86_64-linux-android ;;
    all)
        ABI=arm64-v8a ./make-mpfr.sh
        ABI=armeabi-v7a ./make-mpfr.sh
        ABI=x86 ./make-mpfr.sh
        ABI=x86_64 ./make-mpfr.sh
        echo "Done."
        exit 0 ;;
    *) echo "Unsupported CPU ABI" && exit 1 ;;
esac

case `uname` in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    *) echo "Unsupported OS" && exit 1 ;;
esac
TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/$os-x86_64

if [ -z $API ]; then
    echo "Android API not set. Using 21 by default."
    API=21
fi


export AR=$TOOLCHAIN/bin/llvm-ar
export CC=$TOOLCHAIN/bin/$TARGET$API-clang
export AS=$CC
export CXX=$TOOLCHAIN/bin/$TARGET$API-clang++
export LD=$TOOLCHAIN/bin/ld.lld
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export STRIP=$TOOLCHAIN/bin/llvm-strip
export NM=$TOOLCHAIN/bin/llvm-nm
export OBJDUMP=$TOOLCHAIN/bin/llvm-objdump
export DLLTOOL=$TOOLCHAIN/bin/llvm-dlltool


# Find the GMP header
if [ -z $GMP ] && [ -z $GMPH ]; then
    echo "Please set GMP or GMPH path variable." && exit 1
fi
if [ -z $GMPH ]; then
    GMPH=$GMP
fi
GMPH=$(cd $GMPH; pwd)
if [ ! -f $GMPH/gmp.h ] && [ -d $GMPH/headers ]; then
    GMPH=$GMPH/headers
fi
if [ ! -f $GMPH/gmp.h ] && [ -d $GMPH/$ABI ]; then
    GMPH=$GMPH/$ABI
fi
if [ ! -f $GMPH/gmp.h ]; then
    echo "Can't find the gmp.h header at $GMPH" && exit 1
fi
echo "Found gmp.h header at $GMPH"

# Find the GMP shared libary
if [ -z $GMP ] && [ -z $GMPLIB ]; then
    echo "Please set GMP or GMPLIB path variable." && exit 1
fi
if [ -z $GMPLIB ]; then
    GMPLIB=$GMP
fi
GMPLIB=$(cd $GMPLIB; pwd)
if [ ! -f $GMPLIB/libgmp.so ] && [ -d $GMPLIB/lib ]; then
    GMPLIB=$GMPLIB/lib
fi
if [ ! -f $GMPLIB/libgmp.so ] && [ -d $GMPLIB/$ABI ]; then
    GMPLIB=$GMPLIB/$ABI
fi
if [ ! -f $GMPLIB/libgmp.so ]; then
    echo "Can't find the libgmp.so shared library at $GMPLIB" && exit 1
fi
echo "Found libgmp.so shared library $GMPLIB"


(
cd mpfr ;
ABI= ./configure --disable-static --host $TARGET CFLAGS="-I$GMPH" LDFLAGS="-L$GMPLIB";
make ;
make check-gmp-symbols ;
make check TESTS=
)

# Copy shared library
mkdir -p lib/$ABI
cp mpfr/src/.libs/libmpfr.so lib/$ABI
# ...and headers
mkdir -p headers
cp mpfr/src/mpfr.h headers
cp mpfr/src/mpf2mpfr.h headers
# ...and tests
mkdir -p tests/$ABI
for file in $(cd mpfr/tests; find -type f -perm /111); do
    dir=$(dirname $file)
    mkdir -p tests/$ABI/$dir
    cp mpfr/tests/$file tests/$ABI/$dir
done
