# 🎯 MemeX Prediction Platform

基于Monad链的去中心化meme币预测平台，支持二元期权交易和AI预测辅助。

## 📋 项目概述

这是一个去中心化的预测平台，用户可以对meme币的价格走势进行预测下注。平台特点：

- 🎲 **二元期权**: 简单的YES/NO预测
- 🤖 **AI预测**: 基于自然语言的AI辅助分析
- 💳 **X402支付**: 标准化跨链支付协议
- 🔒 **完全链上**: 所有操作都在链上执行和验证
- ⚡ **自动化**: 从事件生成到结算全程自动化
- 🛡️ **风控完善**: 多层风险保护机制
- 💰 **手续费透明**: 清晰的收入分配模型
- 🌐 **跨链支持**: 原生多链支付和结算

**v2.0 更新**: 采用标准的 X402 协议处理支付，简化架构并提升用户体验。

## 🏗️ 合约架构

### 核心模块

```
📦 PredictionPlatform
├── 🔸 AccessController (权限管理)
├── 🔸 PredictionRouter (统一入口)
├── 🔸 PredictionFactory (事件工厂)
├── 🔸 BinaryOption (单个事件合约)
├── 🔸 PriceOracle (价格预言机)
├── 🔸 RiskManager (风险管理)
└── 🔸 Treasury (资金库)
```

### 各模块功能

- **AccessController**: 权限管理，支持多签和时间锁，紧急暂停/恢复功能
- **PredictionRouter**: 统一用户入口，批量操作支持，智能下注功能
- **PredictionFactory**: 创建和管理预测事件，事件模板管理，活跃事件追踪
- **BinaryOption**: 单个预测事件的核心逻辑，下注、结算、奖金分配，支持多种代币
- **PriceOracle**: Chainlink价格数据集成，TWAP价格计算，价格验证和异常检测
- **RiskManager**: 用户风险评估，熔断器机制，动态参数调整
- **Treasury**: 资金池管理，收入分配，紧急提取

## 🎮 用户流程

### 基础使用流程

1. **浏览事件** → 查看热门meme币预测事件
2. **分析数据** → 查看赔率、资金池、历史数据
3. **AI辅助** → (可选) 通过X402协议支付获取AI预测建议
4. **下注决策** → 选择YES/NO并输入金额
5. **确认交易** → 签名交易，资金锁定到合约
6. **等待结算** → 事件到期后自动结算
7. **领取奖金** → 获胜用户可随时领取奖金

### AI智能投注流程

1. 选择已有预测事件
2. 输入AI分析问题
3. 通过X402协议支付AI服务费用
4. 确认AI推荐的投注方案
5. 系统自动执行投注

### 事件类型

- **价格方向**: ABOVE/BELOW/IN_RANGE/OUT_RANGE
- **涨跌幅**: UP_X%/DOWN_X%
- **持续时间**: 5分钟 - 24小时
- **价格变化**: 1% - 50%
- **最小下注**: 0.001 ETH/USDT
- **最大池子**: 1000 ETH/USDT

## 🛠️ 快速开始

### 环境要求

- Solidity ^0.8.19
- Foundry
- Node.js 16+
- Git

### 安装和编译

```bash
# 克隆项目
git clone <repository-url>
cd memeX

# 安装依赖
forge install
npm install

# 编译合约
forge build

# 运行测试
forge test

# 代码格式化
forge fmt

# Gas消耗分析
forge snapshot
```

### 部署配置

```bash
# 复制环境配置
cp .env.example .env

# 配置必要参数
PRIVATE_KEY=your_private_key_here
OWNER_ADDRESS=your_wallet_address_here
RPC_URL=https://testnet-rpc.monad.xyz
CHAIN_ID=41455

# 合约地址 (部署后填写)
PREDICTION_ROUTER_ADDRESS=0x...
PRICE_ORACLE_ADDRESS=0x...
RISK_MANAGER_ADDRESS=0x...
TREASURY_ADDRESS=0x...
```

### 部署命令

```bash
# 部署到本地测试网
anvil
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

# 部署到测试网
forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

## 🔧 技术特性

### 安全特性
- ✅ **重入攻击防护** (ReentrancyGuard)
- ✅ **暂停/恢复机制** (Pausable)
- ✅ **权限控制** (AccessControl)
- ✅ **时间锁** (Timelock)
- ✅ **多签支持** (Multi-sig)

### 风险控制
- ✅ **用户下注限制** (Bet limits)
- ✅ **池子大小限制** (Pool size limits)
- ✅ **价格变化限制** (Price change limits)
- ✅ **熔断器** (Circuit breaker)
- ✅ **连胜/连败保护** (Streak protection)

### 经济模型
- ✅ **动态赔率** (Dynamic odds)
- ✅ **透明手续费** (3%)
- ✅ **收入分配** (Revenue sharing)
- ✅ **VIP系统** (VIP tiers)
- ✅ **流动性激励** (Liquidity incentives)

## 📊 业务规则

### 下注规则
- 最小下注金额：0.001 ETH/USDT
- 最大下注金额：10,000 ETH/USDT
- 单个事件最大资金池：1,000,000 ETH/USDT
- 平台费用：3%

### AI服务规则
- 基础预测：10 USDC/USDT
- 高级预测：50 USDC/USDT
- 批量预测：100 USDC/USDT
- VIP用户可享受20%折扣
- 通过X402协议处理支付

### 结算规则
- 事件到期后自动结算
- 使用Chainlink价格作为最终价格
- 价格偏差超过5%时触发警报
- 结算后24小时内可领取奖金

### 风险控制
- 用户单日最大风险敞口：50,000 ETH/USDT
- 连胜/连败限制：10次
- 异常行为检测：频率和金额异常
- 系统熔断阈值：500,000 ETH/USDT

## 🧪 测试

```bash
# 运行所有测试
forge test

# 运行特定合约测试
forge test --match-contract BinaryOptionTest

# 运行特定函数测试
forge test --match-test testPlaceBet

# 显示gas使用情况
forge test --gas-report

# 测试覆盖率
forge coverage
```

## ⚡ Gas优化

### 典型Gas消耗
- **创建事件**: ~200,000 gas
- **下注**: ~80,000 gas
- **结算**: ~150,000 gas
- **领取奖金**: ~60,000 gas

### 优化策略
- 使用Libraries减少合约大小
- 紧凑的数据结构
- 事件日志代替存储
- 批量操作支持

## 🔗 网络配置

### Monad 测试网
```env
RPC_URL=https://testnet-rpc.monad.xyz
CHAIN_ID=41455
```

### Monad 主网
```env
RPC_URL=https://rpc.monad.xyz
CHAIN_ID=41454
```

## 🚨 风险提示

### 技术风险
- 智能合约漏洞
- 预言机故障
- 网络拥堵
- MEV攻击

### 市场风险
- 价格操纵
- 流动性不足
- 市场波动
- 监管风险

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

---

⚠️ **免责声明**: 本项目仅用于学习和研究目的，不构成投资建议。智能合约交互存在风险，请谨慎操作。