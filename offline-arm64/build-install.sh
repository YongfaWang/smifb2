#!/bin/bash
#
# Offline build + install of the SiliconMotion SM750/SM768 DRM driver
# for Ubuntu 26.10 (Stonking Stingray) / Linux 7.3 on arm64 (Kunpeng 920).
#
# Usage:
#     cd smifb2-2.6.0
#     sudo ../build-install.sh
#
# The script is written to be re-runnable and to never leave the system in a
# broken state: every step that can fail is checked before it is attempted,
# and nothing is installed into /lib/modules until the module has actually
# been built successfully.
#
# No network access is required.

set -uo pipefail

SRC="${SRC:-$(pwd)}"
KVER="${KVER:-$(uname -r)}"
HDR="/usr/src/linux-headers-${KVER}"
BUILD_LINK="/lib/modules/${KVER}/build"

fail() {
    echo
    echo "!! FAILED: $*" >&2
    echo "!! Nothing has been installed into /lib/modules.  It is safe to fix the" >&2
    echo "!! problem and run this script again." >&2
    exit 1
}

echo "==> Kernel release : ${KVER}"
echo "==> Source tree    : ${SRC}"
echo

# ---------------------------------------------------------------------------
# 0. Sanity checks that do not need root.
# ---------------------------------------------------------------------------
if [ ! -d "${SRC}" ]; then
    fail "source directory '${SRC}' does not exist"
fi

if [ ! -f "${SRC}/Makefile" ]; then
    fail "'${SRC}/Makefile' not found - are you inside the unpacked source tree?"
fi

if ! command -v make >/dev/null 2>&1; then
    fail "make not found.  Install build-essential (offline: use the matching .deb files)."
fi

if ! command -v gcc >/dev/null 2>&1; then
    fail "gcc not found.  Install build-essential (offline: use the matching .deb files)."
fi

# ---------------------------------------------------------------------------
# 1. Locate the kernel headers.
#
# On Ubuntu the distribution header package only populates /usr/src and does
# not create the /lib/modules/<ver>/build symlink that kbuild expects, so
# create it ourselves when it is missing.
# ---------------------------------------------------------------------------
if [ -d "${BUILD_LINK}" ]; then
    echo "==> Kernel headers: ${BUILD_LINK} (already present)"
elif [ -d "${HDR}" ]; then
    # The generic flavour package symlinks large parts of the tree to the
    # base package.  Verify that at least one of those targets resolves
    # BEFORE creating anything, otherwise we would leave a broken link
    # behind on a system that is missing the base package.
    if [ ! -e "${HDR}/include/drm/drm_drv.h" ]; then
        echo "!! '${HDR}/include/drm/drm_drv.h' is missing." >&2
        echo "!! This usually means the base header package is not installed." >&2
        echo "!! Install BOTH linux-headers-<ver> and linux-headers-<ver>-generic." >&2
        fail "incomplete kernel headers"
    fi

    echo "==> Kernel headers: ${HDR}"
    echo "==> Creating ${BUILD_LINK} -> ${HDR}"
    mkdir -p "/lib/modules/${KVER}" || fail "could not create /lib/modules/${KVER}"
    ln -sfn "${HDR}" "${BUILD_LINK}" || fail "could not create the build symlink"
else
    echo "!! Kernel headers for ${KVER} were not found." >&2
    echo "!! Looked for: ${HDR}" >&2
    echo "!! Install them with:" >&2
    echo "!!     sudo dpkg -i debs/linux-headers-${KVER%%-*}_*-generic_*.deb" >&2
    echo "!!     sudo dpkg -i debs/linux-headers-${KVER%%-*}_*_all.deb" >&2
    fail "no kernel headers available"
fi

# Sanity check on the tree we are going to build against.
if [ ! -e "${BUILD_LINK}/include/drm/drm_drv.h" ]; then
    echo "!! '${BUILD_LINK}/include/drm/drm_drv.h' is missing." >&2
    echo "!! The kernel headers look incomplete." >&2
    fail "incomplete kernel headers"
fi

echo

# ---------------------------------------------------------------------------
# 2. Build the out-of-tree module.
#
# Everything is built in a scratch directory first; /lib/modules is only
# touched once we know we have a working .ko.
# ---------------------------------------------------------------------------
echo "==> Building smifb.ko"
echo "    (this can take a couple of minutes)"

BUILD_LOG="${SRC}/build.log"
if ! make -C "${BUILD_LINK}" M="${SRC}" DKMS_BUILD=1 modules > "${BUILD_LOG}" 2>&1; then
    echo "!! Build failed.  Last 40 lines of ${BUILD_LOG}:" >&2
    echo "--------------------------------------------------------------" >&2
    tail -n 40 "${BUILD_LOG}" >&2
    echo "--------------------------------------------------------------" >&2
    fail "compilation failed - see ${BUILD_LOG} for the full log"
fi

if [ ! -f "${SRC}/smifb.ko" ]; then
    fail "the build reported success but ${SRC}/smifb.ko does not exist"
fi

echo "==> Build succeeded:"
echo "    $(ls -l "${SRC}/smifb.ko" | awk '{print $5" bytes"}')"
if command -v modinfo >/dev/null 2>&1; then
    echo "    vermagic: $(modinfo -F vermagic "${SRC}/smifb.ko" 2>/dev/null)"
fi
echo

# ---------------------------------------------------------------------------
# 3. Install the module.
# ---------------------------------------------------------------------------
DEST_DIR="/lib/modules/${KVER}/updates/dkms"

echo "==> Installing to ${DEST_DIR}/smifb.ko"
mkdir -p "${DEST_DIR}" || fail "could not create ${DEST_DIR}"
install -m 0644 "${SRC}/smifb.ko" "${DEST_DIR}/smifb.ko" || fail "could not install the module"

echo "==> Running depmod -a ${KVER}"
depmod -a "${KVER}" || echo "!! depmod reported a problem (may be harmless)" >&2

echo
echo "==================== Installation finished ===================="
echo
echo "The module is installed.  Now load it:"
echo
echo "    sudo modprobe smifb"
echo
echo "Then check that it came up:"
echo
echo "    sudo ../diagnose.sh"
echo
echo "--------------------------------------------------------------"
echo "If modprobe fails, work through these in order:"
echo
echo "1) The in-tree sm750fb driver owns the same PCI ID (126f:0750)."
echo "   If it is loaded, remove it and keep it from loading again:"
echo
echo "     sudo modprobe -r sm750fb"
echo "     echo 'blacklist sm750fb' | sudo tee /etc/modprobe.d/blacklist-sm750fb.conf"
echo
echo "2) The kernel was booted with 'nomodeset'.  Check with:"
echo
echo "     cat /proc/cmdline"
echo
echo "   If 'nomodeset' is present, remove it from GRUB"
echo "   (/etc/default/grub -> GRUB_CMDLINE_LINUX) and run 'sudo update-grub'."
echo
echo "3) Check the log for the real reason:"
echo
echo "     sudo dmesg | tail -40"
echo
echo "To remove the driver again:"
echo
echo "    sudo modprobe -r smifb"
echo "    sudo rm -f ${DEST_DIR}/smifb.ko"
echo "    sudo depmod -a ${KVER}"
