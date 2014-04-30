ios-build-lib
=============

Simple iOS Build Library for Shell Scripts

Usage
-----
```
#!/usr/bin/env bash

# Bootstrap build script
[[ -r ios-build-lib.sh ]] || curl -s -O https://raw.githubusercontent.com/baudm/ios-build-lib/master/ios-build-lib.sh
. ios-build-lib.sh

# Just print out the version of this library
echo $IBL_VERSION

## Environment variables that affect the build

export KEYCHAIN_PATH="/path/to/build.keychain"
export KEYCHAIN_PASSWORD="keychainP@ssword"
# Optional env variables
export PROVISIONING_PROFILE="FFFFFFFF-4444-7777-BBBB-CCCCCCCCCCCC"
export CODE_SIGN_IDENTITY="iPhone Distribution: Some Entity (XXXXXXXXXX)"
# Usually set by Jenkins
export BUILD_NUMBER=917


# Use the current directory as the workspace
ibl_init .

# Invoke xcodebuild using the given parameters
ibl_build -sdk iphoneos -configuration Release | tee "$IBL_BUILD_DIR/xcodebuild.log"

# Package IPA
ipa_filename="$(ibl_package_ipa)"
echo "IPA filename: $ipa_filename"

# Package another IPA using a custom suffix and different profile
ibl_package_ipa "QA" "FFFFFFFF-5555-7777-BBBB-CCCCCCCCCCCC"

# zip dSYM
dsym_filename="$(ibl_archive_dsym)"
echo "dSYM filename: $dsym_filename"

# Don't forget to cleanup
ibl_cleanup

# gzip the build conf for later use, e.g. Crashlytics
gzip -f "$IBL_BUILD_CONF"

# Build artifacts are stored in $IBL_BUILD_DIR
ls "$IBL_BUILD_DIR"
```
