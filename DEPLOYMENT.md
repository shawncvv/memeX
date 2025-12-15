# MemeX 合约部署指南

本文档详细说明如何部署 MemeX 预测平台的智能合约。

**重要更新**: X404PaymentProcessor 已移除，现在使用 X402 协议处理支付，简化了架构并提升了标准化程度。

## 📋 目录

- [环境准备](#环境准备)
- [架构变更说明](#架构变更说明)
- [配置设置](#配置设置)
- [部署步骤](#部署步骤)
- [验证部署](#验证部署)
- [故障排除](#故障排除)
- [网络配置](#网络配置)

## 🏗️ 架构变更说明

### v1.0 → v2.0 主要变更

#### 移除的组件
- ❌ `X404PaymentProcessor.sol` - 支付处理合约
- ❌ `IX404PaymentProcessor.sol` - 支付处理器接口

#### 新的架构
```
原架构:
用户 → 前端 → PredictionRouter → X404PaymentProcessor → 区块链

新架构:
用户 → 前端 → X402协议 → API服务 → 智能合约
```

#### 优势
- ✅ **简化架构**: 移除了冗余的支付处理逻辑
- ✅ **标准化**: 使用行业标准的 X402 支付协议
- ✅ **跨链支持**: 原生支持多链支付
- ✅ **更安全**: 减少了合约攻击面
- ✅ **易维护**: 专注核心业务逻辑

#### 支付流程变更

**旧流程**:
1. 用户调用智能合约
2. 合约调用 X404PaymentProcessor
3. X404PaymentProcessor 处理支付
4. 返回结果给用户

**新流程**:
1. 用户通过前端调用 X402 协议
2. X402 处理跨链支付到 API 服务
3. API 服务验证支付并调用智能合约
4. 智能合约专注处理业务逻辑

## 🔧 环境准备

### 1. 安装依赖

确保已安装以下工具：

```bash
# 安装 Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 验证安装
forge --version
```

### 2. 克隆项目并安装依赖

```bash
git clone <repository-url>
cd memeX
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit
```

## ⚙️ 配置设置

### 1. 环境配置

复制示例配置文件并根据你的环境修改：

```bash
cp .env.example .env
```

### 2. 必需配置项

在 `.env` 文件中配置以下必需项：

```env
# 基础配置
PRIVATE_KEY=your_private_key_here
OWNER_ADDRESS=your_wallet_address_here
MULTISIG_WALLET=your_multisig_wallet_address_here

# 网络配置
RPC_URL=https://testnet-rpc.monad.xyz
CHAIN_ID=41455

# 代币配置
X404_TOKEN_ADDRESS=0x...
USDC_ADDRESS=0x...
USDT_ADDRESS=0x...
```

### 3. 可选配置项

根据需要调整以下参数：

```env
# 风险管理
MAX_POOL_SIZE=1000000000000000000000000
MAX_BET_AMOUNT=10000000000000000000
PLATFORM_FEE_RATE=300

# 财库分配
PLATFORM_RESERVE_SHARE=3000
LIQUIDITY_PROVIDER_SHARE=2500
AI_PROVIDER_SHARE=2500
TEAM_REWARD_SHARE=1000
TREASURY_SHARE=1000
```

## 🚀 部署步骤

### 方法一：一键部署脚本（推荐）

```bash
# 部署到本地网络
./deploy.sh local

# 部署到测试网
./deploy.sh testnet

# 部署到主网（谨慎操作）
./deploy.sh mainnet
```

### 方法二：手动部署

#### 1. 启动本地网络（如果是本地部署）

```bash
anvil --fork-url $RPC_URL
```

#### 2. 编译合约

```bash
forge build --optimize
```

#### 3. 运行测试

```bash
forge test
```

#### 4. 部署合约

```bash
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

## 🔍 验证部署

### 1. 检查合约状态

```bash
# 检查 AccessController 状态
cast call <ACCESS_CONTROLLER_ADDRESS> "owner()" --rpc-url $RPC_URL

# 检查 PredictionRouter 状态
cast call <PREDICTION_ROUTER_ADDRESS> "factory()" --rpc-url $RPC_URL

# 检查 Treasury 状态
cast call <TREASURY_ADDRESS> "platformFeeRate()" --rpc-url $RPC_URL
```

### 2. 验证合约源码

```bash
forge verify-contract <CONTRACT_ADDRESS> <CONTRACT_NAME> \
  --chain-id <CHAIN_ID> \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### 3. 运行集成测试

```bash
forge test --match-test testDeployment -vvv
```

## 🌐 网络配置

### Monad 测试网

```env
RPC_URL=https://testnet-rpc.monad.xyz
CHAIN_ID=41455

# 代币地址 (示例，需要替换为实际地址)
USDC_ADDRESS=0x...
USDT_ADDRESS=0x...

# 价格预言机 (测试网地址)
ETH_USD_FEED=0x...
USDC_USD_FEED=0x...
```

### Monad 主网

```env
RPC_URL=https://rpc.monad.xyz
CHAIN_ID=41454

# 代币地址 (主网地址)
USDC_ADDRESS=0xA0b86a33E6441C78A2Ec44c1e5BeD1C71c3a7Ad42
USDT_ADDRESS=0xdAC17F958D2ee523a2206206994597C13D831ec7

# 价格预言机 (主网地址)
ETH_USD_FEED=0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
USDC_USD_FEED=0xA0b86a33E6441C78A2Ec44c1e5BeD1C71c3a7Ad42
```

### Ethereum 测试网 (Sepolia)

```env
RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_PROJECT_ID
CHAIN_ID=11155111

# Sepolia 测试网代币地址
USDC_ADDRESS=0x...
USDT_ADDRESS=0x...
```

## 🛠️ 部署后配置

### 1. 设置风险参数

```bash
# 设置最大池规模
cast send <RISK_MANAGER_ADDRESS> "setMaxPoolSize(uint256)" 1000000000000000000000000 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# 设置最大下注金额
cast send <RISK_MANAGER_ADDRESS> "setMaxBetAmount(uint256)" 10000000000000000000 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### 2. 配置平台费用

```bash
# 设置平台费率 (3% = 300 基点)
cast send <TREASURY_ADDRESS> "setPlatformFee(uint256)" 300 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### 3. 添加支持的代币

```bash
# 添加新代币支持
cast send <PRICE_ORACLE_ADDRESS> "addPriceFeed(address,address,uint256,uint256)" \
  <TOKEN_ADDRESS> <PRICE_FEED_ADDRESS> 3600 500 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

## ⚠️ 安全注意事项

### 1. 私钥安全

- **永远不要**将私钥提交到版本控制系统
- 使用环境变量或硬件钱包
- 定期轮换部署私钥

### 2. 多签钱包

- 建议使用多签钱包作为合约所有者
- 设置合理的确认阈值和延迟时间
- 定期备份多签钱包

### 3. 权限管理

- 遵循最小权限原则
- 定期审查角色权限
- 使用时间锁保护敏感操作

## 🔧 故障排除

### 常见问题

#### 1. Gas 相关问题

```bash
# 增加 gas limit
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --gas-limit 30000000

# 设置最大 gas 价格
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --max-fee 100000000000  # 100 gwei
```

#### 2. RPC 连接问题

```bash
# 测试 RPC 连接
cast block latest --rpc-url $RPC_URL

# 检查网络状态
cast chainId --rpc-url $RPC_URL
```

#### 3. 合约验证问题

```bash
# 手动验证合约
forge verify-contract <CONTRACT_ADDRESS> <CONTRACT_NAME> \
  --chain-id <CHAIN_ID> \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address,address)" <ARG1> <ARG2>)
```

#### 4. 环境变量问题

```bash
# 检查环境变量
echo $PRIVATE_KEY
echo $RPC_URL

# 加载 .env 文件
source .env
```

### 调试模式

启用详细输出进行调试：

```env
# 在 .env 文件中设置
DEBUG_MODE=true
VERBOSE=true
SAVE_DEPLOYMENT_LOG=true
```

## 📊 监控和维护

### 1. 监控合约事件

```bash
# 监控所有合约事件
cast logs --from-block <DEPLOYMENT_BLOCK> --rpc-url $RPC_URL

# 实时监控
cast logs --follow --address <CONTRACT_ADDRESS> --rpc-url $RPC_URL
```

### 2. 定期维护任务

- 监控 gas 费用和性能指标
- 定期备份合约数据
- 更新价格预言机 feeds
- 审查安全漏洞和更新

### 3. 应急响应

```bash
# 紧急暂停系统
forge script script/Deploy.s.sol --sig "emergencyPause(address)" <ACCESS_CONTROLLER_ADDRESS> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast

# 恢复系统
forge script script/Deploy.s.sol --sig "emergencyUnpause(address)" <ACCESS_CONTROLLER_ADDRESS> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## 📞 支持

如果在部署过程中遇到问题，请：

1. 检查本文档的故障排除部分
2. 查看项目 Issues 页面
3. 联系开发团队

---

**⚠️ 重要提醒**: 主网部署是不可逆操作，请在测试网充分测试后再进行主网部署！