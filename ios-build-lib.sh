#!/usr/bin/env bash
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

declare -xr IBL_VERSION="0.2.0"

ibl_init() {
    # Usually defined by CI software (e.g. Jenkins)
    [[ "$BUILD_NUMBER" ]] || _ibl_warn "BUILD_NUMBER undefined!"

    # Standard variable names used by kpp-management-plugin
    [[ "$KEYCHAIN_PATH" ]] || _ibl_warn "KEYCHAIN_PATH undefined!"
    [[ "$KEYCHAIN_PASSWORD" ]] || _ibl_warn "KEYCHAIN_PASSWORD undefined!"
    [[ "$PROVISIONING_PROFILE" ]] || _ibl_warn "PROVISIONING_PROFILE undefined!"

    # The plugin uses CODE_SIGNING_IDENTITY variable instead of CODE_SIGN_IDENTITY
    [[ "${CODE_SIGN_IDENTITY:=$CODE_SIGNING_IDENTITY}" ]] || _ibl_warn "CODE_SIGN_IDENTITY and CODE_SIGNING_IDENTITY undefined!"

    local -r workspace="$(cd "$(dirname "$1")"; pwd -P)"
    export IBL_BUILD_DIR="$workspace/build"
    mkdir -p "$IBL_BUILD_DIR"
}
readonly -f ibl_init

ibl_cleanup() {
    if [[ -w "$KEYCHAIN_PATH" ]]; then
        security delete-keychain "$KEYCHAIN_PATH"
    fi
}
readonly -f ibl_cleanup

ibl_build() {
    [[ -r "$IBL_BUILD_CONF" ]] || _ibl_dump_config "$@"
    [[ -r "$KEYCHAIN_PATH" ]] && _ibl_prepare_keychain

    . "$IBL_BUILD_CONF"

    # Set build number
    if [[ "$BUILD_NUMBER" ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFOPLIST_FILE"
    else
        export BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFOPLIST_FILE")"
    fi

    _ibl_xcodebuild_args | xargs xcodebuild "$@" clean build | tee "$IBL_BUILD_DIR/xcodebuild.log"
}
readonly -f ibl_build

ibl_package() {
    local -r profile="${1:-$PROVISIONING_PROFILE}"
    local -r suffix="$2"
    local -r profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"

    [[ -r "$IBL_BUILD_CONF" ]] || _ibl_error "Xcode build environment configuration is missing!"
    . "$IBL_BUILD_CONF"

    local tag="$(_ibl_get_build_version)"
    if [[ "$suffix" ]]; then
        tag="${tag}-${suffix}"
    fi

    xcrun -sdk "$SDK_NAME" PackageApplication "$CODESIGNING_FOLDER_PATH" \
        -o "$IBL_BUILD_DIR/${PRODUCT_NAME}_${tag}.ipa" \
        --embed "$profile_dir/${profile}.mobileprovision"
}
readonly -f ibl_package

ibl_archive_dsym() {
    [[ -r "$IBL_BUILD_CONF" ]] || _ibl_error "Xcode build environment configuration is missing!"
    . "$IBL_BUILD_CONF"
    local -r version="$(_ibl_get_build_version)"
    cd "$DWARF_DSYM_FOLDER_PATH"
    zip -r "$IBL_BUILD_DIR/${PRODUCT_NAME}_${version}-dSYM.zip" "$DWARF_DSYM_FILE_NAME"
    cd -
}
readonly -f ibl_archive_dsym

_ibl_error() {
    echo "${FUNCNAME[1]}: error: $@" >&2
    exit 1
}

_ibl_warn() {
    echo "${FUNCNAME[1]}: warning: $@" >&2
}

_ibl_xcodebuild_args() {
    echo SYMROOT=\"$IBL_BUILD_DIR\"
    echo OBJROOT=\"$IBL_BUILD_DIR\"
    # Optional
    [[ "$PROVISIONING_PROFILE" ]] && echo PROVISIONING_PROFILE=\"$PROVISIONING_PROFILE\"
    [[ "$CODE_SIGN_IDENTITY" ]] && echo CODE_SIGN_IDENTITY=\"$CODE_SIGN_IDENTITY\"
    [[ -r "$KEYCHAIN_PATH" ]] && echo OTHER_CODE_SIGN_FLAGS=\"--keychain $KEYCHAIN_PATH\"
}

_ibl_get_build_version() {
    local -r version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFOPLIST_FILE")"
    local -r build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFOPLIST_FILE")"
    printf "${version}-${build}"
}

_ibl_dump_config() {
    export IBL_BUILD_CONF="$IBL_BUILD_DIR/build.conf"
    _ibl_xcodebuild_args | xargs xcodebuild "$@" -showBuildSettings |
        grep -v 'UID' | sed -n "s/^ *\([A-Z_]*\) = \(.*\)$/\1='\2'/p" > "$IBL_BUILD_CONF"
}

_ibl_prepare_keychain() {
    if [[ -z "$(security list-keychains | grep "$KEYCHAIN_PATH")" ]]; then
        # _add_ keychain to the search list, but _keep_ the current search list
        security list-keychains | xargs security list-keychains -s "$KEYCHAIN_PATH"
    fi
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
}
