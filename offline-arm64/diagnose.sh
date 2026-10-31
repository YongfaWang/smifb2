#!/bin/bash
# Diagnostic helper for the SiliconMotion SM750 on Ubuntu 26.10 / Linux 7.3.
# Run as root after the driver has been loaded.

echo "==================== 1. PCI device ===================="
lspci -nnk | grep -iA3 'vga\|display\|SiliconMotion\|126f:' || echo "!! no VGA/display device found"

echo
echo "==================== 2. Kernel ========================="
uname -a

echo
echo "==================== 3. Loaded driver =================="
lsmod | grep -i smifb || echo "!! smifb module is NOT loaded"
ls -l /dev/dri/ 2>/dev/null || echo "!! no /dev/dri devices"

echo
echo "==================== 4. Connector status =============="
if [ -e /sys/class/drm/card0-HDMI-A-1/status ]; then
    for c in /sys/class/drm/card0-*/status; do
        echo "$(dirname "$c" | xargs basename): $(cat "$c")"
    done
else
    echo "!! no DRM connectors found"
fi

echo
echo "==================== 5. Available modes ================"
for c in /sys/class/drm/card0-*/modes; do
    echo "--- $(dirname "$c" | xargs basename) ---"
    cat "$c"
done

echo
echo "==================== 6. EDID ==========================="
if command -v edid-decode >/dev/null 2>&1; then
    for f in /sys/class/drm/card0-*/edid; do
        echo "--- $(dirname "$f" | xargs basename) ---"
        edid-decode "$f" 2>&1 | head -40
    done
else
    echo "(edid-decode not installed; raw EDID below)"
    for f in /sys/class/drm/card0-*/edid; do
        echo "--- $(dirname "$f" | xargs basename) ---"
        od -An -tx1 "$f" | head -8
    done
fi

echo
echo "==================== 7. dmesg (smi) ==================="
dmesg | grep -i -e smifb -e smi_ -e drm | tail -40

echo
echo "==================== 8. Current mode =================="
cat /sys/class/drm/card0-*/modes 2>/dev/null | head -5
for f in /sys/class/drm/card0-*/enabled; do
    echo "$(dirname "$f" | xargs basename): $(cat "$f")"
done

echo
echo "==================== 9. Framebuffer ==================="
cat /sys/class/graphics/fb0/name 2>/dev/null || echo "!! no fb0"
cat /sys/class/graphics/fb0/virtual_size 2>/dev/null
cat /sys/class/graphics/fb0/modes 2>/dev/null
