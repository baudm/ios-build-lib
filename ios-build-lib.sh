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

declare -xr IBL_VERSION="0.5.1"

ibl_init() {
    [[ $# -eq 1 ]] || _ibl_error "Expected path to workspace"

    # Usually defined by CI software (e.g. Jenkins)
    [[ "$BUILD_NUMBER" ]] || _ibl_warn "BUILD_NUMBER undefined!"

    # Standard variable names used by kpp-management-plugin
    [[ "$KEYCHAIN_PATH" ]] || _ibl_warn "KEYCHAIN_PATH undefined!"
    [[ "$KEYCHAIN_PASSWORD" ]] || _ibl_warn "KEYCHAIN_PASSWORD undefined!"
    [[ "$PROVISIONING_PROFILE" ]] || _ibl_warn "PROVISIONING_PROFILE undefined!"

    # The plugin uses CODE_SIGNING_IDENTITY variable instead of CODE_SIGN_IDENTITY
    [[ "${CODE_SIGN_IDENTITY:=$CODE_SIGNING_IDENTITY}" ]] || _ibl_warn "CODE_SIGN_IDENTITY and CODE_SIGNING_IDENTITY undefined!"

    # Control whether to append the build number to the final version string or not
    [[ "$IBL_BUILD_NUMBER_SEPARATOR" ]] || _ibl_warn "IBL_BUILD_NUMBER_SEPARATOR undefined! Not appending the build number to the version."

    local -r workspace="$(cd "$(dirname "$1")"; pwd -P)"

    export IBL_BUILD_DIR="$workspace/build"
    export IBL_BUILD_CONF="$IBL_BUILD_DIR/build.conf"
    export IBL_PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"

    mkdir -p "$IBL_BUILD_DIR"
}
readonly -f ibl_init

ibl_cleanup() {
    [[ $# -eq 0 ]] || _ibl_error "No arguments expected"
    if [[ -w "$KEYCHAIN_PATH" ]]; then
        security delete-keychain "$KEYCHAIN_PATH"
    fi
}
readonly -f ibl_cleanup

ibl_build() {
    [[ -r "$IBL_BUILD_CONF" ]] || _ibl_dump_config "$@"
    . "$IBL_BUILD_CONF"

    [[ -r "$KEYCHAIN_PATH" ]] && _ibl_prepare_keychain

    if [[ "$BUILD_NUMBER" ]]; then
        local -r bundle_version="$BUILD_NUMBER"
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFOPLIST_FILE"
    else
        local -r bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFOPLIST_FILE")"
    fi

    if [[ "$IBL_BUILD_NUMBER_SEPARATOR" ]]; then
        # Append bundle_version/BUILD_NUMBER to the user-visible version string
        local -r version_string="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFOPLIST_FILE")"
        local -r sep="$IBL_BUILD_NUMBER_SEPARATOR"
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version_string}${sep}${bundle_version}" "$INFOPLIST_FILE"
    fi

    _ibl_xcodebuild_args | xargs xcodebuild "$@" clean build
}
readonly -f ibl_build

ibl_package_ipa() {
    [[ $# -le 2 ]] || _ibl_error "Expected a maximum of 2 arguments"
    [[ -r "$IBL_BUILD_CONF" ]] || _ibl_error "Xcode build environment configuration is missing!"
    . "$IBL_BUILD_CONF"

    local -r suffix="$1"
    local -r profile="${2:-$PROVISIONING_PROFILE}"
    #local -r identity="${3:-$CODE_SIGN_IDENTITY}"

    local tag="$(_ibl_get_build_version)"
    [[ "$suffix" ]] && tag="${tag}-${suffix}"
    local -r ipa_filename="${PRODUCT_NAME}_${tag}.ipa"

    xcrun --sdk "$SDK_NAME" PackageApplication "$CODESIGNING_FOLDER_PATH" \
        -o "$IBL_BUILD_DIR/$ipa_filename" \
        --embed "$IBL_PROFILE_DIR/${profile}.mobileprovision" >/dev/null
        #--sign "$identity" \

    printf "$ipa_filename"
}
readonly -f ibl_package_ipa

ibl_archive_dsym() {
    [[ $# -eq 0 ]] || _ibl_error "No arguments expected"
    [[ -r "$IBL_BUILD_CONF" ]] || _ibl_error "Xcode build environment configuration is missing!"
    . "$IBL_BUILD_CONF"

    local -r dsym_filename="${PRODUCT_NAME}_$(_ibl_get_build_version)-dSYM.zip"
    {
        cd "$DWARF_DSYM_FOLDER_PATH"
        zip -r "$IBL_BUILD_DIR/$dsym_filename" "$DWARF_DSYM_FILE_NAME"
        cd -
    } >/dev/null

    printf "$dsym_filename"
}
readonly -f ibl_archive_dsym

ibl_get_profile_uuid() {
    [[ $# -eq 1 ]] || _ibl_error "Expected path to provisioning profile"
    local -r profile="$1"
    egrep --text '[a-zA-Z0-9]{8}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{12}' "$profile" |
        sed 's|.*<string>\([a-zA-Z0-9\-]*\)</string>.*|\1|'
}
readonly -f ibl_get_profile_uuid

ibl_install_profile() {
    [[ $# -eq 1 ]] || _ibl_error "Expected path to provisioning profile"
    local -r profile="$1"
    local -r uuid="$(ibl_get_profile_uuid "$profile")"
    cp -f "$profile" "$IBL_PROFILE_DIR/${uuid}.mobileprovision"
}
readonly -f ibl_install_profile

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
    echo DSTROOT=\"$IBL_BUILD_DIR\"
    echo SHARED_PRECOMPS_DIR=\"$IBL_BUILD_DIR\"
    # Optional
    [[ "$PROVISIONING_PROFILE" ]] && echo PROVISIONING_PROFILE=\"$PROVISIONING_PROFILE\"
    [[ "$CODE_SIGN_IDENTITY" ]] && echo CODE_SIGN_IDENTITY=\"$CODE_SIGN_IDENTITY\"
    [[ -r "$KEYCHAIN_PATH" ]] && echo OTHER_CODE_SIGN_FLAGS=\"--keychain $KEYCHAIN_PATH\"
}

_ibl_get_build_version() {
    # bundle_version/BUILD_NUMBER is already appended to the version string
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFOPLIST_FILE"
}

_ibl_dump_config() {
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
