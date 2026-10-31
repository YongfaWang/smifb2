# SM750 显卡驱动离线部署指南（鲲鹏920 / arm64 / Ubuntu 26.10）

针对你的环境：
- 硬件：鲲鹏920（ARM64 / aarch64）+ SiliconMotion SM750 集成显卡
- 系统：Ubuntu 26.10 "Stonking Stingray"，内核 Linux 7.3.0-9.x
- 约束：服务器**无网络**，只能通过 U 盘拷贝文件

---

## 一、先说结论

| 问题 | 结论 |
|---|---|
| 本项目支持 SM750 吗？ | **支持**。PCI ID `126f:0750` 已在 `smi_drv.c` 的 ID 表中 |
| 支持 ARM64 吗？ | **支持**。`smi_drv.c`、`smi_mode.c` 中有专门的 `__aarch64__` 分支 |
| 支持 Linux 7.3 吗？ | **支持**。仓库 HEAD (v2.6.0) 已加入 `drm_atomic_state` → `drm_atomic_commit` 兼容层（Linux 7.2+ 必需） |
| Ubuntu 26.10 官方仓库的 `smifb2-dkms` 能用吗？ | **不能**。官方版本是 2.4.3，缺少 7.2+ 兼容层，在 7.3 内核上编译失败。**必须用本仓库 v2.6.0** |
| 为什么现在只有 480p？ | 大概率是**驱动根本没装**（走的是 EFI/GOP 兜底显示），或 EDID 读取失败 |
| 能提到更高分辨率吗？ | 能。驱动内建模式表覆盖 1024×768 ~ 1920×1080，最高取决于你的显示器 EDID 和接口（LVDS/TTL/DVI/HDMI） |

---

## 二、U 盘需要带的东西

完整目录长这样：

```
offline-arm64\
├── debs\                                                # 未纳入 Git（见下）
│   ├── linux-headers-7.3.0-9_7.3.0-9.9_all.deb        # 7.3 基础头文件（必需）
│   ├── linux-headers-7.3.0-9-generic_arm64.deb        # 7.3 arm64 头文件（必需）
│   └── smifb2-dkms_2.4.3..._all.deb                    # 官方包（仅作对照，通常不用）
├── src\
│   └── smifb2-2.6.0.tar.gz                              # 本仓库 v2.6.0 源码 ★ 核心
├── build-install.sh                                    # 编译+安装脚本
├── diagnose.sh                                         # 诊断脚本
├── SHA256SUMS                                          # 完整性校验
└── README-offline-arm64.md                             # 本文件
```

### 仓库里存了什么、没存什么

本仓库跟踪脚本、文档和**工具链清单**：
`build-install.sh`、`install-toolchain.sh`、`diagnose.sh`、
`toolchain-manifest.json`、`SHA256SUMS`、本文件。

`debs/` 和 `src/` 下的二进制产物被 `.gitignore` 排除，原因：

- 头文件 + 编译工具链的 deb 合计约 123 MB，会让仓库体积暴涨，且二进制文件无法做 diff 审查
- 这些文件来自 Ubuntu 官方归档，可以随时重新下载
- `toolchain-manifest.json` 记录了全部 49 个包的**精确文件名、版本和字节数**，
  所以离线包可以在任何有网的机器上**完全一致地**重建出来

**在一台有网的机器上准备完整离线包**（这个仓库的根目录下执行）：

```bash
# 1. 驱动源码：直接用本仓库当前版本打包
git archive --format=tar.gz --prefix=smifb2-2.6.0/ \
    -o offline-arm64/src/smifb2-2.6.0.tar.gz HEAD

# 2. 7.3 内核头文件（arm64，两个包必须一起下载）
mkdir -p offline-arm64/debs offline-arm64/src
BASE=https://mirrors.aliyun.com/ubuntu/pool/main/l/linux
curl -L -O "$BASE/linux-headers-7.3.0-9_7.3.0-9.9_all.deb"
curl -L -O "$BASE/linux-headers-7.3.0-9-generic_7.3.0-9.9_arm64.deb"

# 3. 编译工具链（gcc/make/kmod/file 的完整依赖闭包，49 个包）
python3 - <<'PY'
import json, os, urllib.request
base = "https://mirrors.aliyun.com/ubuntu/"
manifest = json.load(open("offline-arm64/toolchain-manifest.json"))
dest = "offline-arm64/debs"
for item in manifest:
    name = item["filename"].split("/")[-1]
    path = os.path.join(dest, name)
    if os.path.exists(path) and os.path.getsize(path) == item["size"]:
        continue
    print("fetching", name, flush=True)
    req = urllib.request.Request(base + item["filename"], headers={"User-Agent": "curl/8"})
    with urllib.request.urlopen(req, timeout=300) as r:
        data = r.read()
    assert len(data) == item["size"], name
    open(path, "wb").write(data)
PY

# 4. 生成校验文件
cd offline-arm64 && sha256sum debs/*.deb src/*.tar.gz > SHA256SUMS
```

> 若目标机器的 `uname -r` 不是 `7.3.0-9-generic`，请按文末 Q8 换成匹配的版本号。

> **注意 1**：如果服务器上已经装了 `linux-headers-$(uname -r)`（`apt install linux-headers-generic`），
> 就不需要带头文件的 deb 了。服务器虽无网络，但如果是刚装系统，通常已预装。
>
> **注意 2**：两个头文件 deb **必须一起安装**。`linux-headers-7.3.0-9-generic` 里的 `include/`、
> `drivers/` 等是指向基础包 `linux-headers-7.3.0-9` 的符号链接，缺一个会编译失败。
>
> **注意 3**：内核版本号要匹配。若服务器 `uname -r` 不是 `7.3.0-9-generic`，
> 这套头文件用不了（见文末"内核版本不一致"的处理）。
>
> **注意 4**：编译工具链的 deb **不区分内核版本**，只要是 arm64 的 Ubuntu 26.10 都能用。
> 如果服务器上已经有 `gcc` 和 `make`，整个 `debs/` 里都可以不带。

---

## 三、部署步骤

> **好消息：离线包里已经包含了完整的编译工具链。**
> 49 个 arm64 的 `.deb`（gcc / make / binutils / libc-dev / kmod / file 及其完整依赖闭包，
> 共 55.5 MB）都在 `debs/` 里。服务器**不需要联网**，也不需要预先装好
> 任何编译环境——脚本会自动检测并安装。

### 第 0 步：把 U 盘插到服务器，拷贝文件

```bash
# 假设 U 盘挂载在 /media/username/USB
cp -r /media/$USER/USB/offline-arm64 /home/$USER/
cd ~/offline-arm64

# 确认关键文件都在
ls debs/gcc*.deb debs/make*.deb debs/linux-headers*.deb src/*.tar.gz
```

### 第 1 步：确认内核与头文件

```bash
uname -r                    # 期望输出类似 7.3.0-9-generic
ls -d /usr/src/linux-headers-$(uname -r)
```

如果提示 `No such file or directory`，说明头文件没装，离线安装：

```bash
# 两个包要一起装，顺序无所谓
sudo dpkg -i debs/linux-headers-7.3.0-9_7.3.0-9.9_all.deb
sudo dpkg -i debs/linux-headers-7.3.0-9-generic_arm64.deb
```

可选：校验 U 盘拷贝过程中文件是否损坏

```bash
sha256sum -c SHA256SUMS
```

### 第 2 步：安装编译工具链（如果服务器上没有）

```bash
# 一条命令即可，全部离线
sudo ./install-toolchain.sh
```

它会安装 `debs/` 里全部 49 个包并打印验证结果：

```
==> gcc: /usr/bin/gcc
      gcc (Ubuntu 15.3.0-4ubuntu1) 15.3.0
==> make: /usr/bin/make
      GNU Make 4.4.1
```

> **如果服务器上已经有 gcc 和 make，这一步可以跳过。**
> 先用 `gcc --version && make --version` 检查一下。

### 第 3 步：解包源码

```bash
tar xzf src/smifb2-2.6.0.tar.gz
cd smifb2-2.6.0
```

### 第 4 步：编译并安装

```bash
# 脚本在仓库里已经带可执行位；如果是从 U 盘拷贝后提示权限不足：
chmod +x ../build-install.sh ../diagnose.sh ../install-toolchain.sh

sudo ../build-install.sh
```

> 也可以用 `bash ../build-install.sh` 运行，这样不需要可执行位。

脚本会：
1. 检查 `gcc` / `make`，**没有就自动从 `debs/` 离线安装**（不必手动跑第 2 步）
2. 检查 `/lib/modules/$(uname -r)/build`，若缺失则从 `/usr/src` 创建软链接
   （Ubuntu 的头文件包**只装到 `/usr/src`，不创建这个链接**，这是最常见的坑）
3. 检查 `include/drm/drm_drv.h` 是否可解析（能分辨出"基础头文件包没装"这类问题）
4. `make -C /lib/modules/$(uname -r)/build M=$PWD modules`
   （日志写到 `build.log`，失败时自动打印最后 40 行）
5. **编译成功之后**才把 `smifb.ko` 装到 `/lib/modules/$(uname -r)/updates/dkms/`
6. `depmod -a`

> 脚本设计成**可重复执行**、**失败不留下半成品**：任何一步失败都会直接退出，
> 并且在编译成功之前不会碰 `/lib/modules`。修好问题后重跑即可。

> **注意**：第 4 步的 make 命令**不能**加 `DKMS_BUILD=1`。源码的 `Makefile`
> 开头是 `ifneq ($(DKMS_BUILD),1)`，一旦设成 1 就不会定义 `obj-m`，
> make 会"成功"但什么都不编译。脚本已经处理好了，手动执行时也要注意。

### 第 5 步：处理与内核自带驱动的冲突（重要）

Ubuntu 26.10 的 arm64 内核**自带** `sm750fb` 驱动（`CONFIG_FB_SM750=m`），
它注册的是**同一个 PCI ID `126f:0750`**，会抢先占用设备，导致 `smifb` 绑定失败。

先看一眼是谁占着：

```bash
ls -l /sys/bus/pci/drivers/*/126f:0750 2>/dev/null
```

如果看到 `sm750fb`，处理掉它：

```bash
# 先卸载
sudo modprobe -r sm750fb

# 再拉黑，确保重启后不会自动加载
echo 'blacklist sm750fb' | sudo tee /etc/modprobe.d/blacklist-sm750fb.conf
```

### 第 6 步：加载驱动

```bash
sudo modprobe smifb
```

如果报 `no such device` 或设备仍被占用，回到第 5 步处理冲突。
如果报 `Unknown symbol` / `invalid module format`，多半是头文件版本和运行中的内核对不上（见 Q8）。

### 第 7 步：验证

```bash
sudo ../diagnose.sh
```

`diagnose.sh` 是**只读**的，不会改动系统；而且刻意没有用 `set -e`，
即使某项检查失败也会继续跑完，最后给出针对你实际状态的"下一步建议"。

---

## 四、关于分辨率（重点）

驱动加载后分辨率由 **EDID** 决定。`smi_mode.c` 的逻辑是：

```
DVI/VGA 连接器
  ├─ drm_get_edid() 成功 → 用显示器上报的模式列表
  └─ 失败/为空        → drm_add_modes_noedid(1920,1080) 兜底
```

所以：

### 情况 A：装完驱动后仍然只有 480p

说明 **EDID 读取失败**。SM750 在 ARM 平台上的 I2C 通道选择和 x86 不一样，先试：

```bash
# 试试硬件 I2C 而不是软件 I2C（SM750 上 hwi2c 更可靠）
sudo modprobe -r smifb
sudo modprobe smifb hwi2c=1
```

如果还是不行，检查显示器接在哪个口上：

```bash
# 强制指定接口（不读 EDID，直接用内建模式表）
#   nopnp 位掩码: bit0=DVI, bit1=VGA, bit2=HDMI
sudo modprobe -r smifb
sudo modprobe smifb nopnp=1 lcd_scale=1 width=1920 height=1080
```

不同的位组合对应不同的物理接口，你按实际接线试。

> **注意**：修改模块参数需要先 `modprobe -r smifb` 卸载再重新加载。
> 只想试参数的话可以用 `modprobe` 的方式一次性传入（见上）。

### 情况 B：显示器是 LVDS 面板（服务器常见）

LVDS 面板必须告诉驱动它的原生分辨率，否则会显示错乱或黑屏：

```bash
# lvds=1 单通道, lvds=2 双通道
sudo modprobe smifb lvds=2 width=1920 height=1080
```

### 情况 C：想固定某个分辨率 + 缩放

```bash
# lcd_scale=1 启用缩放，width/height 为面板原生分辨率
sudo modprobe smifb lvds=2 lcd_scale=1 width=1920 height=1080
```

### 永久生效

编辑 `/etc/modprobe.d/smifb.conf`：

```
options smifb lvds=2 lcd_scale=1 width=1920 height=1080
```

---

## 五、内建模式表支持的分辨率

来自 `ddk750/ddk750_mode.c`，SM750 支持（部分）：

```
800x600    1024x600   1024x768   1152x864   1280x768   1280x800
1280x960   1280x1024  1360x768   1366x768   1440x900   1600x1152
1680x1050  1920x1080  1920x1200  ...
```

刷新率通常 60Hz（部分模式支持 75/85Hz）。

---

## 六、常见问题

### Q1: 编译报 `drm_atomic_state` 找不到 / `struct drm_atomic_commit` 不完整

说明用了旧版源码。确认是 v2.6.0：

```bash
grep -n "drm_atomic_commit" smi_drv.h
```

应该看到 `typedef struct drm_atomic_commit smi_atomic_state;`

### Q2: `make` 报 `No rule to make target` 或找不到 `/lib/modules/.../build`

执行第 4 步脚本里的软链接创建逻辑，或手动：

```bash
sudo mkdir -p /lib/modules/$(uname -r)
sudo ln -sfn /usr/src/linux-headers-$(uname -r) /lib/modules/$(uname -r)/build
```

### Q2b: 服务器上没有 gcc / make 怎么办？

**离线包已经包含了完整的编译工具链**，不需要联网。

```bash
cd ~/offline-arm64
sudo ./install-toolchain.sh
```

它会安装 `debs/` 里的 49 个 arm64 包（gcc / make / binutils / libc-dev / kmod / file 及其完整依赖闭包），
并打印验证结果。

其实第 4 步的 `build-install.sh` **会自动检测**：`gcc` 或 `make` 缺失时，
它会自己从 `debs/` 装好再继续编译。所以你也可以直接跳过这一步，
让脚本来装——两种方式结果一样。

先确认一下服务器现状：

```bash
gcc --version && make --version
```

如果两个都有，工具链那 49 个包根本不用带（省 59 MB）。

### Q3: 装完驱动后 Xorg 报错 / 远程桌面变黑

可能选错了输出接口。可以先用 `nopnp` 强制指定：

```bash
sudo modprobe -r smifb
sudo modprobe smifb nopnp=1 width=1920 height=1080
```

同时检查 `/etc/X11/xorg.conf`：

```
Section "Device"
    Identifier  "SM768"
    Driver      "modesetting"
EndSection
```

### Q4: 需要用 DKMS 吗？

**不必须**。DKMS 需要联网装 `dkms` 包和 `dkms` 依赖，离线环境不划算。直接编译安装即可。

如果确实要用 DKMS，可以把官方 `smifb2-dkms_2.4.3...deb` 的源码换成 v2.6.0 并改 `dkms.conf` 的 `PACKAGE_VERSION`，但**这需要服务器上已有 dkms**。

### Q5: 内核升级后驱动失效

直接编译安装的驱动会随内核升级失效，重跑第 4 步脚本即可（用新内核的 headers）。
注意黑名单文件 `/etc/modprobe.d/blacklist-sm750fb.conf` 会一直生效，不用改。

### Q6: `modprobe smifb` 报 `no such device` / 设备仍被占用

这是**最可能遇到的问题**：Ubuntu 26.10 的 arm64 内核自带 `sm750fb` 驱动
（`CONFIG_FB_SM750=m`），注册的是同一个 PCI ID `126f:0750`。

```bash
# 看谁占着设备
ls -l /sys/bus/pci/drivers/*/126f:0750

# 卸载并拉黑
sudo modprobe -r sm750fb
echo 'blacklist sm750fb' | sudo tee /etc/modprobe.d/blacklist-sm750fb.conf

# 再加载我们的驱动
sudo modprobe smifb
```

`diagnose.sh` 的第 3 节会直接告诉你当前是哪个驱动占着设备。

### Q7: `modprobe smifb` 报 `no devices available`

检查 `/proc/cmdline` 里有没有 `nomodeset`：

```bash
cat /proc/cmdline
```

如果看到 `nomodeset`，说明内核禁用了 modesetting，`smi_init()` 会直接返回 `-ENODEV`：

```c
if (drm_firmware_drivers_only() || !smi_modeset)
        return -ENODEV;
```

去掉它：编辑 `/etc/default/grub` 的 `GRUB_CMDLINE_LINUX`，删除 `nomodeset`，
然后 `sudo update-grub && sudo reboot`。

### Q8: `uname -r` 和我带的头文件版本对不上怎么办？

这套头文件对应 `7.3.0-9-generic`。如果你的服务器内核是别的版本号
（比如 `7.3.0-10-generic` 或 `7.0.0-14-generic`），有两个办法：

**办法 A：在有网的机器上下载匹配版本**（推荐）

```bash
# 在有网的机器上，把 <KVER> 换成服务器实际的 uname -r
apt-get download linux-headers-$(ssh server 'uname -r') \
                   linux-headers-$(ssh server 'uname -r' | cut -d- -f1)-generic
```

Ubuntu 归档路径规律：
`https://mirrors.aliyun.com/ubuntu/pool/main/l/linux/linux-headers-<KVER>_<VER>_<ARCH>.deb`

**办法 B：改用服务器上已有的头文件**

新装的系统通常自带匹配版本的头文件，先检查：

```bash
ls /usr/src/
# 看到 linux-headers-7.3.0-10-generic 就直接用它，不需要带任何 deb
```

这种情况只需要带 `src/smifb2-2.6.0.tar.gz` 和两个脚本就够了。

### Q9: 鲲鹏920 上有没有已知坑？

驱动里有针对 ARM 的专门处理：

- `smi_drv.c` / `smi_mode.c` 中有 `__arm__ || __aarch64__` 分支，
  在 ARM 上**无条件启用 fbdev**（x86 上需要判断 `IORESOURCE_ROM_SHADOW`）
- 也就是说 ARM 平台上驱动一定会注册 `/dev/fb0`，不会出现"装了驱动但没有 fbdev"的情况

但要注意 ARM 平台的 I2C（EDID 读取）通道与 x86 不同，如果 EDID 读不到，
优先尝试 `hwi2c=1`（见"情况 A"）。

另外 ARM 上要留意的是**内核自带的 `sm750fb` 冲突**（见 Q6），
这是 x86 上不存在、但在你这个平台上必然会遇到的问题。

---

## 七、验证成功的标志

```bash
# 1. 模块已加载
lsmod | grep smifb

# 2. 有 DRM 设备
ls /dev/dri/
# card0  renderD128

# 3. 连接器已连接
cat /sys/class/drm/card0-DVI-A-1/status
# connected

# 4. 模式列表包含高分辨率
cat /sys/class/drm/card0-DVI-A-1/modes
# 1920x1080
# 1366x768
# ...

# 5. framebuffer 尺寸正确
cat /sys/class/graphics/fb0/virtual_size
# 1920,1080
```

---

## 八、如果还是不行：一次排查清单

在服务器上依次执行，把输出保存下来（便于带回分析）：

```bash
sudo ../diagnose.sh 2>&1 | tee /tmp/smifb-diag.txt
sudo dmesg | tail -100 > /tmp/smifb-dmesg.txt
uname -r > /tmp/smifb-uname.txt
ls -l /sys/bus/pci/drivers/*/126f:0750 >> /tmp/smifb-diag.txt 2>&1
cat /proc/cmdline >> /tmp/smifb-diag.txt
```

把这三个文件拷回有网的机器上，我可以据此定位问题。

**最可能的三种情况**：

| 症状 | 原因 | 处理 |
|---|---|---|
| `modprobe` 报 `no such device` | 内核自带 `sm750fb` 抢占 | Q6：卸载 + 拉黑 |
| `modprobe` 报 `no devices available` | 内核带 `nomodeset` 启动 | Q7：改 GRUB |
| 驱动加载成功但分辨率还是 480p | EDID 读取失败 | 情况 A：试 `hwi2c=1` / `nopnp` |
