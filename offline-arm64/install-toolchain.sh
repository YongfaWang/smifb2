#!/bin/bash
#
# Install the offline build toolchain from the bundle.
#
# The bundle ships the complete dependency closure of gcc/make for arm64,
# so this works on a machine without any network access.
#
# Usage:
#     sudo ../install-toolchain.sh
#
# It is safe to run this more than once.

set -uo pipefail

BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEBS="${BUNDLE}/debs"

if [ "$(id -u)" -ne 0 ]; then
    echo "!! This script has to be run as root:  sudo $0" >&2
    exit 1
fi

if [ ! -d "${DEBS}" ]; then
    echo "!! ${DEBS} does not exist." >&2
    exit 1
fi

echo "==> Toolchain packages: ${DEBS}"
count="$(ls "${DEBS}"/*.deb 2>/dev/null | wc -l)"
echo "==> ${count} .deb files found"
if [ "${count}" -eq 0 ]; then
    echo "!! No .deb files found in ${DEBS}" >&2
    exit 1
fi

# ---------------------------------------------------------------------
# 1. Install everything with dpkg.  The order inside the directory is
#    not significant here because the bundle contains the full closure.
# ---------------------------------------------------------------------
echo
echo "==> Installing with dpkg -i (order independent)"
DEBIAN_FRONTEND=noninteractive dpkg -i "${DEBS}"/*.deb
dpkg_status=$?

# dpkg -i leaves packages unconfigured when their dependencies are not
# unpacked yet.  A second pass fixes the ordering.
if [ "${dpkg_status}" -ne 0 ]; then
    echo
    echo "==> dpkg reported errors, running a second pass to fix the ordering"
    DEBIAN_FRONTEND=noninteractive dpkg -i "${DEBS}"/*.deb || true
fi

echo
echo "==> Configuring any packages left unpacked"
DEBIAN_FRONTEND=noninteractive dpkg --configure -a || true

# ---------------------------------------------------------------------
# 2. Verify.
# ---------------------------------------------------------------------
echo
echo "==> Verifying the toolchain"
rc=0
for tool in gcc make ld; do
    if command -v "${tool}" >/dev/null 2>&1; then
        echo "    ${tool}: $(command -v "${tool}")"
        "${tool}" --version 2>/dev/null | head -1 | sed 's/^/      /'
    else
        echo "    ${tool}: MISSING"
        rc=1
    fi
done

if [ "${rc}" -ne 0 ]; then
    echo
    echo "!! The toolchain is incomplete.  See the messages above for the" >&2
    echo "!! package that could not be configured." >&2
    exit 1
fi

echo
echo "==> The build toolchain is ready."
echo "    You can now run:  sudo ../build-install.sh"
