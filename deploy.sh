#!/bin/bash

# MemeX 合约一键部署脚本
# 使用方法: ./deploy.sh [local|testnet|mainnet]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 部署网络配置
NETWORK=$1

if [ -z "$NETWORK" ]; then
    log_warning "未指定网络，默认使用本地网络"
    NETWORK="local"
fi

case $NETWORK in
    "local")
        RPC_URL="http://localhost:8545"
        CHAIN_ID="31337"
        VERIFY_FLAG=""
        ;;
    "testnet")
        RPC_URL="https://testnet-rpc.monad.xyz"
        CHAIN_ID="41455"
        VERIFY_FLAG="--verify"
        ;;
    "mainnet")
        RPC_URL="https://rpc.monad.xyz"
        CHAIN_ID="41454"
        VERIFY_FLAG="--verify"
        ;;
    *)
        log_error "不支持的网络: $NETWORK"
        echo "支持的网络: local, testnet, mainnet"
        exit 1
        ;;
esac

log_info "🚀 开始部署 MemeX 合约到 $NETWORK 网络"

# 检查环境变量
check_env_vars() {
    log_info "🔍 检查环境变量..."

    required_vars=("PRIVATE_KEY" "OWNER_ADDRESS" "X404_TOKEN_ADDRESS")
    missing_vars=()

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "缺少以下环境变量:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        log_error "请在 .env 文件中配置这些变量"
        exit 1
    fi

    log_success "环境变量检查通过"
}

# 创建日志目录
create_log_dir() {
    log_info "📁 创建日志目录..."
    mkdir -p logs
    log_success "日志目录创建完成"
}

# 安装依赖
install_dependencies() {
    log_info "📦 安装项目依赖..."

    # 检查是否已安装 OpenZeppelin
    if [ ! -d "lib/openzeppelin-contracts" ]; then
        forge install OpenZeppelin/openzeppelin-contracts --no-commit
        log_success "OpenZeppelin 依赖安装完成"
    else
        log_info "OpenZeppelin 依赖已存在，跳过安装"
    fi

    # 检查是否已安装 forge-std
    if [ ! -d "lib/forge-std" ]; then
        forge install foundry-rs/forge-std --no-commit
        log_success "forge-std 依赖安装完成"
    else
        log_info "forge-std 依赖已存在，跳过安装"
    fi
}

# 编译合约
compile_contracts() {
    log_info "🔨 编译合约..."

    if [ "$SKIP_TESTS" = "true" ]; then
        forge build --optimize
    else
        forge build --optimize
    fi

    log_success "合约编译完成"
}

# 运行测试
run_tests() {
    if [ "$SKIP_TESTS" != "true" ]; then
        log_info "🧪 运行测试..."
        forge test --gas-report
        log_success "测试通过"
    else
        log_warning "跳过测试 (SKIP_TESTS=true)"
    fi
}

# 部署合约
deploy_contracts() {
    log_info "🚀 开始部署合约..."
    log_info "网络: $NETWORK"
    log_info "RPC URL: $RPC_URL"

    # 构建部署命令
    DEPLOY_CMD="forge script script/Deploy.s.sol \
        --rpc-url $RPC_URL \
        --private-key $PRIVATE_KEY \
        --broadcast"

    # 添加验证标志
    if [ -n "$VERIFY_FLAG" ] && [ "$AUTO_VERIFY_CONTRACTS" = "true" ]; then
        DEPLOY_CMD="$DEPLOY_CMD $VERIFY_FLAG"
        if [ -n "$ETHERSCAN_API_KEY" ]; then
            DEPLOY_CMD="$DEPLOY_CMD --etherscan-api-key $ETHERSCAN_API_KEY"
        fi
    fi

    # 添加 gas 限制
    if [ -n "$GAS_LIMIT" ]; then
        DEPLOY_CMD="$DEPLOY_CMD --gas-limit $GAS_LIMIT"
    fi

    log_info "执行部署命令: $DEPLOY_CMD"

    # 执行部署
    eval $DEPLOY_CMD

    log_success "合约部署完成"
}

# 验证部署
verify_deployment() {
    log_info "🔍 验证部署..."

    # 这里可以添加更多验证逻辑
    # 例如检查合约地址、调用函数等

    log_success "部署验证完成"
}

# 保存部署信息
save_deployment_info() {
    if [ "$SAVE_DEPLOYMENT_LOG" = "true" ]; then
        log_info "💾 保存部署信息..."

        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        LOG_FILE="$DEPLOYMENT_LOG_PATH"

        echo "========================================" >> $LOG_FILE
        echo "部署时间: $(date)" >> $LOG_FILE
        echo "网络: $NETWORK" >> $LOG_FILE
        echo "Chain ID: $CHAIN_ID" >> $LOG_FILE
        echo "RPC URL: $RPC_URL" >> $LOG_FILE
        echo "部署者: $OWNER_ADDRESS" >> $LOG_FILE
        echo "========================================" >> $LOG_FILE

        log_success "部署信息已保存到 $LOG_FILE"
    fi
}

# 显示部署后信息
show_post_deploy_info() {
    log_success "🎉 部署完成！"
    echo ""
    log_info "📋 后续步骤:"
    echo "1. 检查合约输出中的合约地址"
    echo "2. 更新前端配置文件中的合约地址"
    echo "3. 设置 AI 预言机合约地址"
    echo "4. 配置实际的价格预言机 feeds"
    echo "5. 根据需要调整风险参数"
    echo ""
    log_info "📊 监控命令:"
    echo "# 监控合约事件"
    echo "cast logs --from-block <DEPLOYMENT_BLOCK> --address <CONTRACT_ADDRESS> --rpc-url $RPC_URL"
    echo ""
    log_info "🔧 管理命令:"
    echo "# 暂停系统"
    echo "forge script script/Deploy.s.sol:s emergencyPause <ACCESS_CONTROLLER_ADDRESS> --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast"
    echo ""
}

# 主函数
main() {
    # 显示部署信息
    echo "=========================================="
    echo "🚀 MemeX 合约自动部署脚本"
    echo "=========================================="
    echo "网络: $NETWORK"
    echo "Chain ID: $CHAIN_ID"
    echo "RPC URL: $RPC_URL"
    echo "=========================================="
    echo ""

    # 执行部署流程
    check_env_vars
    create_log_dir
    install_dependencies
    compile_contracts
    run_tests
    deploy_contracts
    verify_deployment
    save_deployment_info
    show_post_deploy_info
}

# 捕获错误
trap 'log_error "部署过程中发生错误，请检查日志"; exit 1' ERR

# 执行主函数
main