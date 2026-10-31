#!/bin/bash
# Offline build + install of the SiliconMotion SM750/SM768 DRM driver
# for Ubuntu 26.10 (Stonking Stingray) / Linux 7.3 on arm64 (Kunpeng 920).
#
# Run from the directory containing the unpacked smifb2 source tree.
# No network access is required.

set -euo pipefail

SRC="${SRC:-$(pwd)}"
KVER="${KVER:-$(uname -r)}"
HDR="/usr/src/linux-headers-${KVER}"
BUILD_LINK="/lib/modules/${KVER}/build"

echo "==> Kernel release : ${KVER}"
echo "==> Source tree    : ${SRC}"

# ---------------------------------------------------------------------------
# 1. Locate the kernel headers.
#
# On Ubuntu the distribution header package only populates /usr/src and does
# not create the /lib/modules/<ver>/build symlink that kbuild expects, so
# create it ourselves when it is missing.
# ---------------------------------------------------------------------------
if [ ! -d "${BUILD_LINK}" ]; then
    if [ -d "${HDR}" ]; then
        echo "==> Creating ${BUILD_LINK} -> ${HDR}"
        mkdir -p "/lib/modules/${KVER}"
        ln -sfn "${HDR}" "${BUILD_LINK}"
    else
        echo "!! Kernel headers for ${KVER} not found under /usr/src." >&2
        echo "!! Install linux-headers-${KVER} (and its -generic flavour) first." >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# 2. Build the out-of-tree module.
# ---------------------------------------------------------------------------
echo "==> Building smifb.ko against ${BUILD_LINK}"
make -C "${BUILD_LINK}" M="${SRC}" DKMS_BUILD=1 modules

# ---------------------------------------------------------------------------
# 3. Install into /lib/modules/$(uname -r)/updates/dkms and run depmod.
# ---------------------------------------------------------------------------
echo "==> Installing module"
install -D -m 0644 "${SRC}/smifb.ko" "/lib/modules/${KVER}/updates/dkms/smifb.ko"

echo "==> Running depmod"
depmod -a "${KVER}"

echo "==> Done. Load it with:"
echo "      sudo modprobe smifb"
