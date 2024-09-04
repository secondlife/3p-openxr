#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

OPENXR_SOURCE_DIR="openxr"

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" ]] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

stage="$(pwd)/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

pushd "$OPENXR_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            load_vsvars

            mkdir -p "build"
            pushd "build"

            opts="$(replace_switch /Zi /Z7 $LL_BUILD_RELEASE)"
            plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

            cmake .. -G "Ninja Multi-Config" -DBUILD_SHARED_LIBS=OFF -DDYNAMIC_LOADER=OFF \
                    -DCMAKE_C_FLAGS="$plainopts" \
                    -DCMAKE_CXX_FLAGS="$opts" \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)" \
                    -DCMAKE_INSTALL_LIBDIR="$(cygpath -m $stage/lib/release)"

            cmake --build . --config Release
            cmake --install . --config Release

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                ctest -C Release
            fi

            popd
        ;;
        darwin*)
            export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

            for arch in x86_64 arm64 ; do
                ARCH_ARGS="-arch $arch"
                cxx_opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
                cc_opts="$(remove_cxxstd $cxx_opts)"
                ld_opts="$ARCH_ARGS -Wl,-install_name,\"${install_name}\" -Wl,-headerpad_max_install_names"

                mkdir -p "build_$arch"
                pushd "build_$arch"
                    cmake .. -G "Ninja Multi-Config" -DBUILD_SHARED_LIBS:BOOL=OFF -DDYNAMIC_LOADER=OFF \
                        -DCMAKE_BUILD_TYPE="Release" \
                        -DCMAKE_C_FLAGS="$cc_opts" \
                        -DCMAKE_CXX_FLAGS="$cxx_opts" \
                        -DCMAKE_INSTALL_PREFIX="$stage" \
                        -DCMAKE_INSTALL_LIBDIR="$stage/lib/release/$arch" \
                        -DCMAKE_OSX_ARCHITECTURES="$arch" \
                        -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET}

                    cmake --build . --config Release
                    cmake --install . --config Release

                    # conditionally run unit tests
                    if [ "${DISABLE_UNIT_TESTS:-0}" = "0" -a "$arch" = "$(uname -m)" ]; then
                        ctest -C Release
                    fi
                popd
            done

            lipo -create -output "$stage/lib/release/libopenxr_loader.a" "$stage/lib/release/x86_64/libopenxr_loader.a" "$stage/lib/release/arm64/libopenxr_loader.a" 

        ;;
        linux*)
            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"

            # Release
            mkdir -p "build"
            pushd "build"
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF -DDYNAMIC_LOADER=OFF \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$(remove_cxxstd $opts)" \
                    -DCMAKE_CXX_FLAGS="$opts" \
                    -DCMAKE_INSTALL_PREFIX="$stage"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp "LICENSE" "$stage/LICENSES/openxr.txt"
popd
