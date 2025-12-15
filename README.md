# 🎯 Meme Prediction Platform

基于Monad链的meme币预测平台，支持二元期权交易和AI预测辅助。

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

**v2.0 更新**: 移除了 X404PaymentProcessor，采用标准的 X402 协议处理支付，简化架构并提升用户体验。

## 🏗️ 合约架构

### 核心模块

```
📦 PredictionPlatform
├── 🔸 AccessController (权限管理)
├── 🔸 PredictionRouter (统一入口)
├── 🔸 PredictionFactory (事件工厂)
├── 🔸 BinaryOption (单个事件合约)
├── 🔸 PriceOracle (价格预言机)
├── 🔸 X404PaymentProcessor (支付处理)
├── 🔸 RiskManager (风险管理)
└── 🔸 Treasury (资金库)
```

### 详细说明

#### 1. AccessController
- 管理所有合约的访问权限
- 支持多签和时间锁
- 紧急暂停/恢复功能

#### 2. PredictionRouter
- 统一的用户入口
- 批量操作支持
- 智能下注功能

#### 3. PredictionFactory
- 创建和管理预测事件
- 事件模板管理
- 活跃事件追踪

#### 4. BinaryOption
- 单个预测事件的核心逻辑
- 下注、结算、奖金分配
- 支持多种代币

#### 5. PriceOracle
- Chainlink价格数据集成
- TWAP价格计算
- 价格验证和异常检测

#### 6. X404PaymentProcessor
- AI预测费用处理
- VIP等级折扣系统
- 批量支付支持

#### 7. RiskManager
- 用户风险评估
- 熔断器机制
- 动态参数调整

#### 8. Treasury
- 资金池管理
- 收入分配
- 紧急提取

## 🎮 使用流程

### 用户操作流程

1. **浏览事件** → 查看热门meme币预测事件
2. **分析数据** → 查看赔率、资金池、历史数据
3. **AI辅助** → (可选) 支付X404获取AI预测建议
4. **下注决策** → 选择YES/NO并输入金额
5. **确认交易** → 签名交易，资金锁定到合约
6. **等待结算** → 事件到期后自动结算
7. **领取奖金** → 获胜用户可随时领取奖金

### 事件生成

1. **数据获取** → 从nad.fun获取热门meme前20
2. **参数生成** → 随机生成事件类型和目标价格
3. **合约部署** → 通过工厂合约创建事件
4. **状态监控** → 自动监控事件状态变化

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
- ✅ **透明手续费** (Transparent fees)
- ✅ **收入分配** (Revenue sharing)
- ✅ **VIP系统** (VIP tiers)
- ✅ **流动性激励** (Liquidity incentives)

## 📊 事件类型

### 价格方向事件
- `ABOVE`: 价格超过目标价格
- `BELOW`: 价格低于目标价格
- `IN_RANGE`: 价格在指定区间内
- `OUT_RANGE`: 价格不在指定区间内

### 涨跌幅事件
- `UP_X%`: 相比基准价格上涨X%
- `DOWN_X%`: 相比基准价格下跌X%

### 参数范围
- **持续时间**: 5分钟 - 24小时
- **价格变化**: 1% - 50%
- **最小下注**: 0.001 ETH/USDT
- **最大池子**: 1000 ETH/USDT

## 🛠️ 部署指南

### 环境要求
- Solidity ^0.8.19
- Foundry
- Node.js 16+
- Git

### Foundry 快速开始

#### Build
```bash
forge build
```

#### Test
```bash
forge test
```

#### Format
```bash
forge fmt
```

#### Gas Snapshots
```bash
forge snapshot
```

#### Deploy
```bash
forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### 完整部署步骤

1. **克隆项目**
```bash
git clone <repository-url>
cd memeX
```

2. **安装依赖**
```bash
forge install
npm install
```

3. **配置环境变量**
```bash
cp .env.example .env
# 编辑 .env 文件，设置必要的环境变量
```

4. **运行测试**
```bash
forge test
```

5. **部署到本地测试网**
```bash
anvil # 启动本地节点
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
```

## 🧪 测试

### 运行测试
```bash
# 运行所有测试
forge test

# 运行特定合约测试
forge test --match-contract BinaryOptionTest

# 运行特定函数测试
forge test --match-test testPlaceBet

# 显示gas使用情况
forge test --gas-report
```

### 测试覆盖率
```bash
forge coverage
```

## 📈 Gas优化

### 优化策略
- 使用Libraries减少合约大小
- 紧凑的数据结构
- 事件日志代替存储
- 批量操作支持

### 典型Gas消耗
- **创建事件**: ~200,000 gas
- **下注**: ~80,000 gas
- **结算**: ~150,000 gas
- **领取奖金**: ~60,000 gas

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

## 🔮 未来计划

### 短期目标 (1-2个月)
- [ ] 完成安全审计
- [ ] 部署到测试网
- [ ] 前端界面开发
- [ ] AI服务集成

### 中期目标 (3-6个月)
- [ ] 主网部署
- [ ] 流动性挖矿
- [ ] DAO治理
- [ ] 多链支持

### 长期目标 (6-12个月)
- [ ] 衍生品交易
- [ ] NFT奖励系统
- [ ] 跨链桥接
- [ ] 移动端应用

## 🤝 贡献指南

### 开发流程
1. Fork项目
2. 创建功能分支
3. 提交代码
4. 创建Pull Request
5. 代码审查
6. 合并到主分支

### 代码规范
- 遵循Solidity最佳实践
- 添加详细的注释
- 编写测试用例
- 更新文档

## 📞 联系方式

- **项目主页**: [GitHub](https://github.com/your-repo)
- **文档**: [Docs](https://docs.your-site.com)
- **社区**: [Discord](https://discord.gg/your-server)
- **Twitter**: [@YourHandle](https://twitter.com/YourHandle)

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

---

⚠️ **免责声明**: 本项目仅用于学习和研究目的，不构成投资建议。智能合约交互存在风险，请谨慎操作。
