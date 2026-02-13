#!/bin/bash
#
# 使用 QEMU 测试 Task 1 内核
#
# 无需 sudo 权限
#

KERNEL_DIR="/disk/scratch/operating_systems/s2279011/linux-6.12.67"
KERNEL_IMG="$KERNEL_DIR/arch/x86/boot/bzImage"

# 检查内核是否已编译
if [ ! -f "$KERNEL_IMG" ]; then
    echo "错误: 未找到内核镜像 $KERNEL_IMG"
    echo ""
    echo "请先编译内核:"
    echo "  cd $KERNEL_DIR"
    echo "  make defconfig"
    echo "  make -j\$(nproc)"
    exit 1
fi

echo "=========================================="
echo "  使用 QEMU 启动内核"
echo "=========================================="
echo ""
echo "内核: $KERNEL_IMG"
echo ""

# 使用 QEMU 启动内核（无磁盘，使用 initramfs）
# -smp 2 表示 2 个 CPU
qemu-system-x86_64 \
    -kernel "$KERNEL_IMG" \
    -smp 2 \
    -m 512M \
    -nographic \
    -append "console=ttyS0 panic=1" \
    -no-reboot

echo ""
echo "QEMU 已退出"
