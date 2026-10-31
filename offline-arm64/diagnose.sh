#!/bin/bash
#
# Diagnostic helper for the SiliconMotion SM750 on Ubuntu 26.10 / Linux 7.3.
#
# Usage:
#     sudo ../diagnose.sh
#
# This script is read-only: it never modifies the system.  Every section
# keeps going even when something is missing, so a single run gives you the
# complete picture.
#
# 'set -e' is deliberately NOT used: a missing file or an empty grep result
# must never abort the run half way through.

set -uo pipefail

echo "==================== 1. PCI device ===================="
if command -v lspci >/dev/null 2>&1; then
    lspci -nnk | grep -iA3 'vga\|display\|SiliconMotion\|126f:' || echo "!! no VGA/display device found"
else
    echo "(lspci not installed)"
    echo "--- /sys/bus/pci/devices scan ---"
    for d in /sys/bus/pci/devices/*/; do
        v=$(cat "$d/vendor" 2>/dev/null)
        if [ "$v" = "0x126f" ]; then
            echo "  found SiliconMotion device: $(basename "$d") device=$(cat "$d/device" 2>/dev/null)"
        fi
    done
fi

echo
echo "==================== 2. Kernel ========================="
uname -a
echo "--- expected headers ---"
ls -d /usr/src/linux-headers-$(uname -r) 2>/dev/null || echo "!! /usr/src/linux-headers-$(uname -r) missing"
ls -ld /lib/modules/$(uname -r)/build 2>/dev/null || echo "!! /lib/modules/$(uname -r)/build missing"

echo
echo "==================== 3. Loaded driver =================="
lsmod | grep -i smifb || echo "!! smifb module is NOT loaded"
echo "--- competing in-tree driver ---"
lsmod | grep -i sm750fb && echo "!! sm750fb is loaded and may own the device (blacklist it)" || echo "    sm750fb not loaded - good"
ls -l /dev/dri/ 2>/dev/null || echo "!! no /dev/dri devices"
echo "--- driver bound to the GPU ---"
for d in /sys/bus/pci/drivers/*/; do
    n=$(basename "$d")
    if [ -e "$d/126f:0750" ]; then
        echo "    $n owns 126f:0750"
    fi
done

echo
echo "==================== 4. Connector status =============="
found=0
for c in /sys/class/drm/card0-*/status; do
    [ -e "$c" ] || continue
    found=1
    echo "$(basename "$(dirname "$c")"): $(cat "$c" 2>/dev/null)"
done
[ "$found" -eq 0 ] && echo "!! no DRM connectors found"

echo
echo "==================== 5. Available modes ================"
found=0
for c in /sys/class/drm/card0-*/modes; do
    [ -e "$c" ] || continue
    found=1
    echo "--- $(basename "$(dirname "$c")") ---"
    cat "$c" 2>/dev/null
done
[ "$found" -eq 0 ] && echo "!! no mode lists found"

echo
echo "==================== 6. EDID ==========================="
found=0
for f in /sys/class/drm/card0-*/edid; do
    [ -e "$f" ] || continue
    found=1
    echo "--- $(basename "$(dirname "$f")") ---"
    if command -v edid-decode >/dev/null 2>&1; then
        edid-decode "$f" 2>&1 | head -40
    else
        echo "(edid-decode not installed; raw EDID below)"
        od -An -tx1 "$f" 2>/dev/null | head -8
    fi
done
[ "$found" -eq 0 ] && echo "!! no EDID files found"

echo
echo "==================== 7. dmesg (smi) ==================="
dmesg 2>/dev/null | grep -i -e smifb -e sm750fb -e smi_ -e 'drm' | tail -40 || echo "(no matching messages)"

echo
echo "==================== 8. Current mode =================="
for c in /sys/class/drm/card0-*/modes; do
    [ -e "$c" ] || continue
    echo "--- $(basename "$(dirname "$c")") ---"
    head -5 "$c" 2>/dev/null
done
for f in /sys/class/drm/card0-*/enabled; do
    [ -e "$f" ] || continue
    echo "$(basename "$(dirname "$f")"): $(cat "$f" 2>/dev/null)"
done

echo
echo "==================== 9. Framebuffer ==================="
cat /sys/class/graphics/fb0/name 2>/dev/null || echo "!! no fb0"
cat /sys/class/graphics/fb0/virtual_size 2>/dev/null
cat /sys/class/graphics/fb0/modes 2>/dev/null

echo
echo "==================== 10. Next steps ===================="
if lsmod | grep -qi smifb; then
    echo "Driver loaded.  If the resolution is still 480p, check section 5"
    echo "(available modes) and section 6 (EDID) above:"
    echo
    echo "  * No EDID at all -> try hardware I2C:  sudo modprobe -r smifb && sudo modprobe smifb hwi2c=1"
    echo "  * EDID present but no high resolutions -> the panel may need a fixed mode:"
    echo "        sudo modprobe -r smifb"
    echo "        sudo modprobe smifb lvds=2 lcd_scale=1 width=1920 height=1080"
    echo "  * Connector stuck at 'disconnected' -> force it (bit0=DVI bit1=VGA bit2=HDMI):"
    echo "        sudo modprobe -r smifb && sudo modprobe smifb nopnp=1"
else
    echo "Driver is NOT loaded.  Try:"
    echo
    echo "    sudo modprobe smifb"
    echo
    echo "If that fails with 'no such device', the in-tree sm750fb driver owns the"
    echo "device.  Blacklist it and retry:"
    echo
    echo "    echo 'blacklist sm750fb' | sudo tee /etc/modprobe.d/blacklist-sm750fb.conf"
    echo "    sudo modprobe -r sm750fb"
    echo "    sudo modprobe smifb"
fi
echo
