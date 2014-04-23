#!/bin/sh
#
# The MIT License (MIT)
# 
# Copyright (c) 2014 Darwin Bautista
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

export IBL_VERSION="0.1.0"

ibl_init() {
    [ -n "$KEYCHAIN_PATH" ] || _ibl_error "KEYCHAIN_PATH undefined!"
    [ -n "$KEYCHAIN_PASSWORD" ] || _ibl_error "KEYCHAIN_PASSWORD undefined!"
    [ -n "$PROVISIONING_PROFILE" ] || _ibl_warn "PROVISIONING_PROFILE undefined!"
    [ -n "$CODE_SIGN_IDENTITY" ] || _ibl_warn "CODE_SIGN_IDENTITY undefined!"
    [ -n "$BUILD_NUMBER" ] || _ibl_warn "BUILD_NUMBER undefined!"

    local workspace="`cd $(dirname $1); pwd -P`"
    export IBL_BUILD_DIR="$workspace/build"
    mkdir -p "$IBL_BUILD_DIR"
}

ibl_cleanup() {
    security delete-keychain "$KEYCHAIN_PATH"
}

ibl_build() {
    [ -f "$IBL_BUILD_CONF" ] || _ibl_dump_config "$@"
    _ibl_keychain_is_ready || _ibl_prepare_keychain

    . "$IBL_BUILD_CONF"

    # Set build number
    if [ -n "$BUILD_NUMBER" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFOPLIST_FILE"
    else
        export BUILD_NUMBER="`/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFOPLIST_FILE"`"
    fi

    _ibl_xcodebuild_args | xargs xcodebuild "$@" clean build \
        OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH" |
        tee "$IBL_BUILD_DIR/xcodebuild.log"
}

ibl_package() {
    local profile="$1"
    local suffix="$2"
    local profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"

    [ -f "$IBL_BUILD_CONF" ] || _ibl_error "Xcode build environment configuration is missing!"
    . "$IBL_BUILD_CONF"

    [ -n "$profile" ] || profile="$PROVISIONING_PROFILE"

    tag="`_ibl_get_build_version`"
    [ -n "$suffix" ] && tag="${tag}-${suffix}"

    xcrun -sdk "$SDK_NAME" PackageApplication -v "$CODESIGNING_FOLDER_PATH" \
        -o "$IBL_BUILD_DIR/${PRODUCT_NAME}_${tag}.ipa" \
        --embed "$profile_dir/${profile}.mobileprovision"
}

ibl_archive_dsym() {
    [ -f "$IBL_BUILD_CONF" ] || _ibl_error "Xcode build environment configuration is missing!"
    . "$IBL_BUILD_CONF"
    local version="`_ibl_get_build_version`"
    cd "$DWARF_DSYM_FOLDER_PATH"
    zip -r "$IBL_BUILD_DIR/${PRODUCT_NAME}_${version}-dSYM.zip" "$DWARF_DSYM_FILE_NAME"
    cd -
}

_ibl_error() {
    echo "ios-build: $@" 1>&2
    exit 1
}

_ibl_warn() {
    echo "ios-build: $@" 1>&2
}

_ibl_xcodebuild_args() {
    echo SYMROOT=\"$IBL_BUILD_DIR\"
    echo OBJROOT=\"$IBL_BUILD_DIR\"
    # Optional
    [ -n "$PROVISIONING_PROFILE" ] && echo PROVISIONING_PROFILE=\"$PROVISIONING_PROFILE\"
    [ -n "$CODE_SIGN_IDENTITY" ] && echo CODE_SIGN_IDENTITY=\"$CODE_SIGN_IDENTITY\"
}

_ibl_get_build_version() {
    local version="`/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFOPLIST_FILE"`"
    local build="`/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFOPLIST_FILE"`"
    printf "${version}-${build}"
}

_ibl_dump_config() {
    export IBL_BUILD_CONF="$IBL_BUILD_DIR/build.conf"
    _ibl_xcodebuild_args | xargs xcodebuild "$@" -showBuildSettings |
        grep -v 'UID' | sed -n "s/^ *\([A-Z_]*\) = \(.*\)$/export \1='\2'/p" > "$IBL_BUILD_CONF"
}

_ibl_prepare_keychain() {
    # _add_ keychain to the search list, but _keep_ the current search list
    security list-keychains | xargs security list-keychains -s "$KEYCHAIN_PATH"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
}

_ibl_keychain_is_ready() {
    if [ -n "`security list-keychains | grep "$KEYCHAIN_PATH"`" ]; then
        return 1
    else
        return 0
    fi
}
