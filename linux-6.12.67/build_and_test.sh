#!/bin/bash
#
# 编译内核并使用 QEMU 测试
# 无需 sudo 权限
#

set -e

KERNEL_DIR="/disk/scratch/operating_systems/s2279011/linux-6.12.67"
INITRAMFS_DIR="$KERNEL_DIR/initramfs"
KERNEL_IMG="$KERNEL_DIR/arch/x86/boot/bzImage"

cd "$KERNEL_DIR"

echo "=========================================="
echo "  Step 1: 配置内核"
echo "=========================================="

if [ ! -f .config ]; then
    echo "创建默认配置..."
    make defconfig

    # 启用一些必要选项
    ./scripts/config --enable CONFIG_BLK_DEV_INITRD
    ./scripts/config --enable CONFIG_RD_GZIP
    ./scripts/config --enable CONFIG_DEVTMPFS
    ./scripts/config --enable CONFIG_DEVTMPFS_MOUNT
    ./scripts/config --enable CONFIG_TTY
    ./scripts/config --enable CONFIG_SERIAL_8250
    ./scripts/config --enable CONFIG_SERIAL_8250_CONSOLE
    ./scripts/config --enable CONFIG_PROC_FS
    ./scripts/config --enable CONFIG_SYSFS
    ./scripts/config --enable CONFIG_SMP

    make olddefconfig
fi

echo ""
echo "=========================================="
echo "  Step 2: 编译内核"
echo "=========================================="

make -j$(nproc)

if [ ! -f "$KERNEL_IMG" ]; then
    echo "错误: 编译失败"
    exit 1
fi

echo ""
echo "内核编译成功: $KERNEL_IMG"

echo ""
echo "=========================================="
echo "  Step 3: 创建 initramfs"
echo "=========================================="

# 创建 initramfs 目录结构
rm -rf "$INITRAMFS_DIR"
mkdir -p "$INITRAMFS_DIR"/{bin,sbin,etc,proc,sys,dev,tmp,root}

# 复制 busybox（如果系统有的话）
if command -v busybox &> /dev/null; then
    cp $(which busybox) "$INITRAMFS_DIR/bin/"

    # 创建常用命令的符号链接
    cd "$INITRAMFS_DIR/bin"
    for cmd in sh ash ls cat echo mkdir mount umount ps grep sleep; do
        ln -sf busybox $cmd 2>/dev/null || true
    done
    cd "$KERNEL_DIR"
else
    echo "警告: 未找到 busybox，尝试编译静态版本..."

    # 下载并编译 busybox
    if [ ! -f "$KERNEL_DIR/busybox" ]; then
        echo "请手动安装 busybox 或从以下地址下载:"
        echo "  https://busybox.net/downloads/binaries/"
        echo ""
        echo "下载后放到: $KERNEL_DIR/busybox"
        exit 1
    fi
fi

# 创建 init 脚本
cat > "$INITRAMFS_DIR/init" << 'INIT_SCRIPT'
#!/bin/sh

# 挂载必要的文件系统
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || mknod /dev/console c 5 1

# 显示欢迎信息
echo ""
echo "=========================================="
echo "  Linux Kernel Task 1 测试环境"
echo "=========================================="
echo ""

# 显示 CPU 信息
echo "CPU 数量: $(grep -c processor /proc/cpuinfo)"
echo ""

# 检查纠缠 CPU 接口
if [ -f /proc/sys/kernel/entangled_cpus_1 ]; then
    echo "纠缠 CPU 接口已启用!"
    echo "  /proc/sys/kernel/entangled_cpus_1 = $(cat /proc/sys/kernel/entangled_cpus_1)"
    echo "  /proc/sys/kernel/entangled_cpus_2 = $(cat /proc/sys/kernel/entangled_cpus_2)"
    echo ""
    echo "设置纠缠 CPU:"
    echo "  echo 0 > /proc/sys/kernel/entangled_cpus_1"
    echo "  echo 1 > /proc/sys/kernel/entangled_cpus_2"
else
    echo "警告: 未找到纠缠 CPU 接口"
    echo "请检查内核是否正确编译"
fi

echo ""
echo "启动 shell..."
echo ""

# 启动 shell
exec /bin/sh
INIT_SCRIPT

chmod +x "$INITRAMFS_DIR/init"

# 创建 initramfs.cpio.gz
cd "$INITRAMFS_DIR"
find . | cpio -H newc -o 2>/dev/null | gzip > "$KERNEL_DIR/initramfs.cpio.gz"
cd "$KERNEL_DIR"

echo "initramfs 创建完成: $KERNEL_DIR/initramfs.cpio.gz"

echo ""
echo "=========================================="
echo "  Step 4: 启动 QEMU"
echo "=========================================="
echo ""
echo "按 Ctrl+A 然后 X 退出 QEMU"
echo ""

qemu-system-x86_64 \
    -kernel "$KERNEL_IMG" \
    -initrd "$KERNEL_DIR/initramfs.cpio.gz" \
    -smp 2 \
    -m 512M \
    -nographic \
    -append "console=ttyS0 init=/init panic=1" \
    -no-reboot
