#!/bin/bash
#
# Task 1 测试脚本：测试纠缠 CPU 的跨 CPU 互斥
#
# 使用方法：sudo ./test_task1.sh
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
CPU1=0
CPU2=1
TEST_USER1="testuser1"
TEST_USER2="testuser2"
TEST_DURATION=15  # 测试持续时间（秒）

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Task 1 纠缠 CPU 互斥测试脚本${NC}"
echo -e "${YELLOW}========================================${NC}"

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 sudo 运行此脚本${NC}"
    exit 1
fi

# 检查 CPU 数量
NUM_CPUS=$(nproc)
echo -e "${GREEN}[INFO]${NC} 检测到 $NUM_CPUS 个 CPU"

if [ "$NUM_CPUS" -lt 2 ]; then
    echo -e "${RED}[ERROR]${NC} 需要至少 2 个 CPU"
    exit 1
fi

# 检查 procfs 接口是否存在
if [ ! -f /proc/sys/kernel/entangled_cpus_1 ]; then
    echo -e "${RED}[ERROR]${NC} /proc/sys/kernel/entangled_cpus_1 不存在"
    echo -e "${RED}请确保已经启动了修改后的内核${NC}"
    exit 1
fi

# 创建测试用户
create_test_users() {
    echo -e "${GREEN}[INFO]${NC} 创建测试用户..."

    if ! id "$TEST_USER1" &>/dev/null; then
        useradd -m "$TEST_USER1" 2>/dev/null || true
        echo -e "${GREEN}[INFO]${NC} 创建用户 $TEST_USER1 (UID: $(id -u $TEST_USER1))"
    else
        echo -e "${GREEN}[INFO]${NC} 用户 $TEST_USER1 已存在 (UID: $(id -u $TEST_USER1))"
    fi

    if ! id "$TEST_USER2" &>/dev/null; then
        useradd -m "$TEST_USER2" 2>/dev/null || true
        echo -e "${GREEN}[INFO]${NC} 创建用户 $TEST_USER2 (UID: $(id -u $TEST_USER2))"
    else
        echo -e "${GREEN}[INFO]${NC} 用户 $TEST_USER2 已存在 (UID: $(id -u $TEST_USER2))"
    fi
}

# 清理函数
cleanup() {
    echo -e "\n${YELLOW}[CLEANUP]${NC} 清理测试进程..."
    pkill -f "test_busy_task1" 2>/dev/null || true

    # 重置纠缠 CPU 设置
    echo 0 > /proc/sys/kernel/entangled_cpus_1
    echo 0 > /proc/sys/kernel/entangled_cpus_2
    echo -e "${GREEN}[INFO]${NC} 已重置纠缠 CPU 设置"

    # 删除临时文件
    rm -f /tmp/test_busy_task1.sh
    rm -f /tmp/cpu_monitor_*.log

    echo -e "${GREEN}[CLEANUP]${NC} 清理完成"
}

# 设置 trap 确保退出时清理
trap cleanup EXIT INT TERM

# 创建 CPU 密集型测试程序
create_test_program() {
    cat > /tmp/test_busy_task1.sh << 'SCRIPT'
#!/bin/bash
# CPU 密集型测试程序
echo "Started: PID=$$, UID=$(id -u), CPU=$1"
exec taskset -c $1 sh -c 'while true; do :; done'
SCRIPT
    chmod +x /tmp/test_busy_task1.sh
}

# 设置纠缠 CPU
setup_entangled_cpus() {
    echo -e "${GREEN}[INFO]${NC} 设置纠缠 CPU 对: CPU $CPU1 <-> CPU $CPU2"
    echo $CPU1 > /proc/sys/kernel/entangled_cpus_1
    echo $CPU2 > /proc/sys/kernel/entangled_cpus_2

    # 验证设置
    local c1=$(cat /proc/sys/kernel/entangled_cpus_1)
    local c2=$(cat /proc/sys/kernel/entangled_cpus_2)
    echo -e "${GREEN}[INFO]${NC} 验证: entangled_cpus_1=$c1, entangled_cpus_2=$c2"
}

# 监控 CPU 使用情况
monitor_cpus() {
    local duration=$1
    local logfile="/tmp/cpu_monitor_$$.log"

    echo -e "${GREEN}[INFO]${NC} 开始监控 CPU 使用情况 ($duration 秒)..."
    echo ""
    echo "时间戳 | 进程 | 用户 | CPU | 状态"
    echo "--------------------------------------------"

    for ((i=0; i<duration; i++)); do
        # 获取测试进程的 CPU 分配情况
        ps -eo pid,user,psr,stat,comm 2>/dev/null | grep "test_busy_task1" | while read line; do
            echo "$(date +%H:%M:%S) | $line"
        done
        sleep 1
    done
}

# 运行测试
run_test() {
    local test_name=$1
    local user1=$2
    local user2=$3
    local cpu1=$4
    local cpu2=$5

    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}测试: $test_name${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${GREEN}[INFO]${NC} 用户1: $user1 -> CPU $cpu1"
    echo -e "${GREEN}[INFO]${NC} 用户2: $user2 -> CPU $cpu2"
    echo ""

    # 启动用户1的进程
    sudo -u "$user1" /tmp/test_busy_task1.sh $cpu1 &
    local pid1=$!
    sleep 0.5

    # 启动用户2的进程
    sudo -u "$user2" /tmp/test_busy_task1.sh $cpu2 &
    local pid2=$!
    sleep 0.5

    echo -e "${GREEN}[INFO]${NC} 进程已启动: PID1=$pid1, PID2=$pid2"

    # 监控
    monitor_cpus $TEST_DURATION

    # 停止测试进程
    pkill -f "test_busy_task1" 2>/dev/null || true
    sleep 1
}

# 分析结果
analyze_results() {
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}测试结果分析${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo "预期行为:"
    echo "  1. 同一用户在两个纠缠 CPU: 都能正常运行"
    echo "  2. 不同用户在两个纠缠 CPU: 互斥，同一时刻只有一个用户的进程运行"
    echo "  3. 阻塞超过 10 秒后: 触发 handoff，被阻塞的用户可以运行"
    echo ""
    echo "请观察上面的监控输出，检查:"
    echo "  - 不同用户的进程是否同时出现在 CPU $CPU1 和 CPU $CPU2"
    echo "  - 进程状态 (R=运行, S=睡眠, D=等待)"
    echo ""
}

# 主函数
main() {
    create_test_users
    create_test_program
    setup_entangled_cpus

    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}测试 1: 不同用户在纠缠 CPU 对${NC}"
    echo -e "${YELLOW}(预期: 互斥，不能同时运行)${NC}"
    echo -e "${YELLOW}========================================${NC}"

    run_test "不同用户互斥测试" "$TEST_USER1" "$TEST_USER2" $CPU1 $CPU2

    analyze_results

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  测试完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# 运行主函数
main
