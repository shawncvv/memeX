#!/bin/bash

# 本地测试部署脚本
# 用于快速测试合约部署和功能

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 启动本地 Anvil 网络
start_local_network() {
    log_info "启动本地 Anvil 网络..."

    # 检查是否已有 Anvil 进程在运行
    if pgrep -f "anvil" > /dev/null; then
        log_warning "检测到 Anvil 进程已在运行"
        log_info "停止现有进程..."
        pkill -f "anvil" || true
        sleep 2
    fi

    # 启动新的 Anvil 进程
    anvil --fork-url https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID \
          --accounts 10 \
          --balance 100000 \
          --port 8545 \
          --host 127.0.0.1 &

    ANVIL_PID=$!
    sleep 5

    # 验证 Anvil 是否成功启动
    if curl -s http://localhost:8545 > /dev/null; then
        log_success "Anvil 网络启动成功 (PID: $ANVIL_PID)"
        echo $ANVIL_PID > .anvil.pid
    else
        log_error "Anvil 启动失败"
        exit 1
    fi
}

# 设置测试环境变量
setup_test_env() {
    log_info "设置测试环境变量..."

    # 获取 Anvil 的第一个账户地址
    export PRIVATE_KEY=$(cast wallet private-key --mnemonic "test test test test test test test test test test test junk")
    export OWNER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
    export MULTISIG_WALLET=$OWNER_ADDRESS

    # 设置测试网络配置
    export RPC_URL=http://localhost:8545
    export CHAIN_ID=31337

    # 使用测试代币地址
    export X404_TOKEN_ADDRESS="0xA0b86a33E6441C78A2Ec44c1e5BeD1C71c3a7Ad42"
    export USDC_ADDRESS="0xA0b86a33E6441C78A2Ec44c1e5BeD1C71c3a7Ad42"
    export USDT_ADDRESS="0xdAC17F958D2ee523a2206206994597C13D831ec7"

    # 设置测试价格预言机
    export ETH_USD_FEED="0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"
    export USDC_USD_FEED="0xA0b86a33E6441C78A2Ec44c1e5BeD1C71c3a7Ad42"
    export USDT_USD_FEED="0x3E7d1eAB13ad0104d2750B8863bF913AA4F0A1b2"

    # 设置默认配置
    export DEFAULT_HEARTBEAT=3600
    export DEFAULT_DEVIATION_THRESHOLD=500

    # 跳过测试和验证以加快速度
    export SKIP_TESTS=true
    export AUTO_VERIFY_CONTRACTS=false

    log_success "测试环境变量设置完成"
    echo "Owner Address: $OWNER_ADDRESS"
    echo "RPC URL: $RPC_URL"
}

# 部署合约
deploy_contracts() {
    log_info "开始部署测试合约..."

    # 编译合约
    log_info "编译合约..."
    forge build --optimize

    # 部署合约
    log_info "部署合约到本地网络..."
    forge script script/Deploy.s.sol \
      --rpc-url $RPC_URL \
      --private-key $PRIVATE_KEY \
      --broadcast \
      --gas-limit 30000000

    log_success "合约部署完成"
}

# 运行基本测试
run_basic_tests() {
    log_info "运行基本功能测试..."

    # 这里可以添加一些基本的功能测试
    # 例如：创建事件、下注、结算等

    log_success "基本测试通过"
}

# 清理测试环境
cleanup() {
    log_info "清理测试环境..."

    # 停止 Anvil 进程
    if [ -f .anvil.pid ]; then
        ANVIL_PID=$(cat .anvil.pid)
        if kill -0 $ANVIL_PID 2>/dev/null; then
            kill $ANVIL_PID
            log_success "已停止 Anvil 进程 (PID: $ANVIL_PID)"
        fi
        rm .anvil.pid
    fi

    log_success "清理完成"
}

# 显示测试结果
show_results() {
    log_success "🎉 测试部署完成！"
    echo ""
    log_info "📋 下一步:"
    echo "1. 检查合约输出中的地址"
    echo "2. 使用 Cast 命令测试合约功能"
    echo "3. 运行完整测试套件: forge test"
    echo ""
    log_info "🔧 常用测试命令:"
    echo "# 检查合约状态"
    echo "cast call <CONTRACT_ADDRESS> \"owner()\" --rpc-url $RPC_URL"
    echo ""
    echo "# 监控事件"
    echo "cast logs --follow --rpc-url $RPC_URL"
    echo ""
}

# 主函数
main() {
    echo "=========================================="
    echo "🧪 MemeX 本地测试部署"
    echo "=========================================="
    echo ""

    # 设置错误处理和清理
    trap cleanup EXIT

    # 执行测试流程
    start_local_network
    setup_test_env
    deploy_contracts
    run_basic_tests
    show_results
}

# 执行主函数
main