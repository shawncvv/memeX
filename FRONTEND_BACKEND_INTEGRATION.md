# MemeX 前后端与智能合约交互详细指南

本文档详细说明前后端如何与 memeX 智能合约系统进行交互，包括所有接口、事件监听、最佳实践和代码示例。

## 📋 目录

- [系统架构概览](#系统架构概览)
- [前端与合约交互](#前端与合约交互)
- [后端与合约交互](#后端与合约交互)
- [合约ABI和事件监听](#合约abi和事件监听)
- [安全最佳实践](#安全最佳实践)
- [性能优化建议](#性能优化建议)

## 🏗️ 系统架构概览

### 核心合约架构

```
Frontend/Backend ↔ PredictionRouter (主入口)
                    ↕
            ┌───────┴───────┐
            ↓               ↓
    PredictionFactory   X404PaymentProcessor
            ↓               ↓
    BinaryOption     RiskManager ↔ Treasury
            ↓               ↓
      PriceOracle     AccessController
```

### 主要交互流程

1. **用户操作** → `PredictionRouter` → 分发到各个功能合约
2. **价格查询** → `PriceOracle` → Chainlink 数据源
3. **风险管理** → `RiskManager` → 用户行为分析和限制
4. **资金管理** → `Treasury` → 费用收集和分配

---

## 🎨 前端与合约交互

### 1. 环境设置和连接

#### Web3 提供者配置

```typescript
// utils/web3.ts
import { ethers } from 'ethers';
import { PredictionRouterABI } from './abis/PredictionRouter';
import { BinaryOptionABI } from './abis/BinaryOption';
import { PriceOracleABI } from './abis/PriceOracle';

// 合约地址配置
const CONTRACT_ADDRESSES = {
  PREDICTION_ROUTER: '0x...',
  PRICE_ORACLE: '0x...',
  RISK_MANAGER: '0x...',
  TREASURY: '0x...',
};

export class Web3Service {
  private provider: ethers.BrowserProvider;
  private signer: ethers.JsonRpcSigner;

  // 主要合约实例
  public predictionRouter: ethers.Contract;
  public priceOracle: ethers.Contract;

  async initialize() {
    // 连接 MetaMask 或其他钱包
    if (typeof window.ethereum !== 'undefined') {
      this.provider = new ethers.BrowserProvider(window.ethereum);
      await window.ethereum.request({ method: 'eth_requestAccounts' });
      this.signer = await this.provider.getSigner();

      // 初始化合约实例
      this.predictionRouter = new ethers.Contract(
        CONTRACT_ADDRESSES.PREDICTION_ROUTER,
        PredictionRouterABI,
        this.signer
      );

      this.priceOracle = new ethers.Contract(
        CONTRACT_ADDRESSES.PRICE_ORACLE,
        PriceOracleABI,
        this.signer
      );

      return true;
    }
    throw new Error('Web3 provider not found');
  }

  // 获取用户地址
  async getUserAddress(): Promise<string> {
    return await this.signer.getAddress();
  }

  // 获取网络信息
  async getNetworkInfo() {
    const network = await this.provider.getNetwork();
    return {
      chainId: Number(network.chainId),
      name: network.name,
    };
  }

  // 切换网络
  async switchNetwork(chainId: number) {
    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: `0x${chainId.toString(16)}` }],
      });
    } catch (error) {
      // 如果网络不存在，尝试添加网络
      if (error.code === 4902) {
        await this.addNetwork(chainId);
      }
    }
  }

  private async addNetwork(chainId: number) {
    // 根据不同的链ID添加网络配置
    const networkConfigs = {
      41454: { // Monad Mainnet
        chainName: 'Monad',
        rpcUrls: ['https://rpc.monad.xyz'],
        nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
      },
      41455: { // Monad Testnet
        chainName: 'Monad Testnet',
        rpcUrls: ['https://testnet-rpc.monad.xyz'],
        nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
      },
    };

    const config = networkConfigs[chainId];
    if (config) {
      await window.ethereum.request({
        method: 'wallet_addEthereumChain',
        params: [{
          chainId: `0x${chainId.toString(16)}`,
          ...config,
        }],
      });
    }
  }
}
```

### 2. 核心功能交互

#### 2.1 创建和参与预测事件

```typescript
// services/predictionService.ts
import { ethers } from 'ethers';
import { Web3Service } from './web3';

export class PredictionService {
  constructor(private web3Service: Web3Service) {}

  // 创建事件并立即下注
  async createAndBet(params: {
    token: string;
    targetPrice: string;
    duration: number;
    description: string;
    betAmount: string;
    position: 'YES' | 'NO';
    betToken: string;
    useAI: boolean;
    aiQuestion?: string;
  }) {
    const eventParams = {
      token: params.token,
      targetPrice: ethers.parseEther(params.targetPrice),
      duration: params.duration,
      description: params.description,
    };

    const position = params.position === 'YES' ? 0 : 1; // YES = 0, NO = 1

    try {
      const tx = await this.web3Service.predictionRouter.createAndBet(
        eventParams,
        position,
        ethers.parseEther(params.betAmount),
        params.betToken,
        params.useAI,
        params.aiQuestion || '',
        {
          value: params.betToken === '0x0000000000000000000000000000000000000000'
            ? ethers.parseEther(params.betAmount)
            : 0,
          gasLimit: 300000,
        }
      );

      // 等待交易确认
      const receipt = await tx.wait();

      return {
        transactionHash: receipt.hash,
        blockNumber: receipt.blockNumber,
        eventAddress: this.extractEventAddress(receipt),
        aiRequestId: this.extractAIRequestId(receipt),
      };
    } catch (error) {
      throw new Error(`创建事件和下注失败: ${error.message}`);
    }
  }

  // 智能投注（AI辅助）
  async intelligentBet(params: {
    eventAddress: string;
    betAmount: string;
    betToken: string;
    aiQuestion: string;
  }) {
    try {
      const tx = await this.web3Service.predictionRouter.intelligentBet(
        params.eventAddress,
        ethers.parseEther(params.betAmount),
        params.betToken,
        params.aiQuestion,
        {
          value: params.betToken === '0x0000000000000000000000000000000000000000'
            ? ethers.parseEther(params.betAmount)
            : 0,
          gasLimit: 300000,
        }
      );

      const receipt = await tx.wait();

      return {
        transactionHash: receipt.hash,
        blockNumber: receipt.blockNumber,
        aiRequestId: this.extractAIRequestId(receipt),
        recommendedPosition: this.extractRecommendedPosition(receipt),
      };
    } catch (error) {
      throw new Error(`智能投注失败: ${error.message}`);
    }
  }

  // 批量下注
  async batchBet(bets: Array<{
    eventAddress: string;
    position: 'YES' | 'NO';
    amount: string;
    token: string;
    useAI: boolean;
    aiQuestion?: string;
  }>) {
    const eventAddresses = bets.map(b => b.eventAddress);
    const positions = bets.map(b => b.position === 'YES' ? 0 : 1);
    const amounts = bets.map(b => ethers.parseEther(b.amount));
    const tokens = bets.map(b => b.token);
    const useAIs = bets.map(b => b.useAI);
    const aiQuestions = bets.map(b => b.aiQuestion || '');

    try {
      const tx = await this.web3Service.predictionRouter.batchBet(
        eventAddresses,
        positions,
        amounts,
        tokens,
        useAIs,
        aiQuestions,
        {
          gasLimit: 500000 * bets.length, // 根据下注数量动态调整
        }
      );

      const receipt = await tx.wait();

      return {
        transactionHash: receipt.hash,
        blockNumber: receipt.blockNumber,
        successfulBets: this.extractSuccessfulBets(receipt),
        failedBets: this.extractFailedBets(receipt),
      };
    } catch (error) {
      throw new Error(`批量下注失败: ${error.message}`);
    }
  }

  // 领取奖金
  async claimWinnings(eventAddresses: string[]) {
    try {
      const tx = await this.web3Service.predictionRouter.batchClaimWinnings(
        eventAddresses,
        { gasLimit: 200000 * eventAddresses.length }
      );

      const receipt = await tx.wait();

      return {
        transactionHash: receipt.hash,
        blockNumber: receipt.blockNumber,
        claimedAmounts: this.extractClaimedAmounts(receipt),
      };
    } catch (error) {
      throw new Error(`领取奖金失败: ${error.message}`);
    }
  }

  // 提取事件地址（私有辅助方法）
  private extractEventAddress(receipt: any): string {
    const event = receipt.logs.find(log =>
      log.topics[0] === ethers.id('CreateAndBet(address,address,uint8,uint256,address)')
    );
    return event ? ethers.AbiCoder.defaultAbiCoder().decode(['address'], event.data)[0] : '';
  }

  // 其他提取方法类似...
}
```

#### 2.2 价格查询和事件状态

```typescript
// services/priceService.ts
import { ethers } from 'ethers';
import { Web3Service } from './web3';

export class PriceService {
  constructor(private web3Service: Web3Service) {}

  // 获取代币当前价格
  async getCurrentPrice(tokenAddress: string): Promise<string> {
    try {
      const price = await this.web3Service.priceOracle.getLatestPrice(tokenAddress);
      return ethers.formatEther(price);
    } catch (error) {
      throw new Error(`获取价格失败: ${error.message}`);
    }
  }

  // 获取历史价格
  async getHistoricalPrice(tokenAddress: string, timestamp: number): Promise<string> {
    try {
      const price = await this.web3Service.priceOracle.getHistoricalPrice(
        tokenAddress,
        timestamp
      );
      return ethers.formatEther(price);
    } catch (error) {
      throw new Error(`获取历史价格失败: ${error.message}`);
    }
  }

  // 获取价格变化趋势
  async getPriceTrend(tokenAddress: string, hours: number): Promise<{
    currentPrice: string;
    change24h: number;
    trend: 'up' | 'down' | 'stable';
  }> {
    try {
      const currentPrice = await this.getCurrentPrice(tokenAddress);
      const pastTimestamp = Math.floor(Date.now() / 1000) - (hours * 3600);
      const pastPrice = await this.getHistoricalPrice(tokenAddress, pastTimestamp);

      const changePercent = ((parseFloat(currentPrice) - parseFloat(pastPrice)) / parseFloat(pastPrice)) * 100;

      let trend: 'up' | 'down' | 'stable' = 'stable';
      if (changePercent > 2) trend = 'up';
      else if (changePercent < -2) trend = 'down';

      return {
        currentPrice,
        change24h: changePercent,
        trend,
      };
    } catch (error) {
      throw new Error(`获取价格趋势失败: ${error.message}`);
    }
  }

  // 验证价格数据有效性
  async validatePriceData(tokenAddress: string): Promise<boolean> {
    try {
      return await this.web3Service.priceOracle.validatePrice(tokenAddress, 0);
    } catch (error) {
      console.error('价格验证失败:', error);
      return false;
    }
  }
}
```

#### 2.3 事件状态管理

```typescript
// services/eventService.ts
import { ethers } from 'ethers';
import { BinaryOptionABI } from '../abis/BinaryOption';

export interface EventInfo {
  address: string;
  token: string;
  targetPrice: string;
  currentPrice: string;
  description: string;
  startTime: number;
  endTime: number;
  status: 'OPEN' | 'LOCKED' | 'SETTLED' | 'CANCELLED';
  yesPool: string;
  noPool: string;
  yesOdds: string;
  noOdds: string;
  totalPrizePool: string;
  userBets: UserBet[];
}

export interface UserBet {
  user: string;
  position: 'YES' | 'NO';
  amount: string;
  timestamp: number;
  winnings: string;
  claimed: boolean;
}

export class EventService {
  constructor(private web3Service: Web3Service) {}

  // 获取事件详情
  async getEventDetails(eventAddress: string): Promise<EventInfo> {
    try {
      const eventContract = new ethers.Contract(
        eventAddress,
        BinaryOptionABI,
        this.web3Service.provider
      );

      const [
        eventInfo,
        currentOdds,
        userAddress
      ] = await Promise.all([
        eventContract.getEventInfo(),
        eventContract.getCurrentOdds(),
        this.web3Service.getUserAddress()
      ]);

      const [
        token,
        targetPrice,
        description,
        startTime,
        endTime,
        status,
        yesPool,
        noPool
      ] = eventInfo;

      const currentPrice = await this.getCurrentPrice(token);
      const userBets = await this.getUserBets(eventAddress, userAddress);

      return {
        address: eventAddress,
        token,
        targetPrice: ethers.formatEther(targetPrice),
        currentPrice,
        description,
        Number(startTime),
        Number(endTime),
        status: this.mapStatus(Number(status)),
        yesPool: ethers.formatEther(yesPool),
        noPool: ethers.formatEther(noPool),
        yesOdds: ethers.formatEther(currentOdds[0]),
        noOdds: ethers.formatEther(currentOdds[1]),
        totalPrizePool: ethers.formatEther(yesPool + noPool),
        userBets,
      };
    } catch (error) {
      throw new Error(`获取事件详情失败: ${error.message}`);
    }
  }

  // 获取用户活跃事件
  async getUserActiveEvents(userAddress?: string): Promise<EventInfo[]> {
    try {
      const address = userAddress || await this.web3Service.getUserAddress();
      const eventAddresses = await this.web3Service.predictionRouter.getUserActiveEvents(address);

      const eventDetails = await Promise.all(
        eventAddresses.map(addr => this.getEventDetails(addr))
      );

      return eventDetails;
    } catch (error) {
      throw new Error(`获取用户活跃事件失败: ${error.message}`);
    }
  }

  // 获取所有活跃事件
  async getActiveEvents(): Promise<EventInfo[]> {
    try {
      // 这里需要通过事件工厂或其他方式获取活跃事件列表
      // 或者通过事件日志来收集
      const events = await this.queryActiveEvents();

      const eventDetails = await Promise.all(
        events.map(addr => this.getEventDetails(addr))
      );

      return eventDetails.filter(event =>
        event.status === 'OPEN' || event.status === 'LOCKED'
      );
    } catch (error) {
      throw new Error(`获取活跃事件失败: ${error.message}`);
    }
  }

  // 检查事件是否可结算
  async canEventBeSettled(eventAddress: string): Promise<boolean> {
    try {
      const eventContract = new ethers.Contract(
        eventAddress,
        BinaryOptionABI,
        this.web3Service.provider
      );

      const info = await eventContract.getEventInfo();
      const currentTime = Math.floor(Date.now() / 1000);

      return Number(info[4]) <= currentTime && Number(info[5]) === 0; // OPEN状态且已过期
    } catch (error) {
      return false;
    }
  }

  // 获取用户在特定事件中的下注
  private async getUserBets(eventAddress: string, userAddress: string): Promise<UserBet[]> {
    try {
      const eventContract = new ethers.Contract(
        eventAddress,
        BinaryOptionABI,
        this.web3Service.provider
      );

      const bets = await eventContract.getUserBets(userAddress);

      return bets.map(bet => ({
        user: bet.user,
        position: bet.position === 0 ? 'YES' : 'NO',
        amount: ethers.formatEther(bet.amount),
        timestamp: Number(bet.timestamp),
        winnings: ethers.formatEther(bet.winnings),
        claimed: bet.claimed,
      }));
    } catch (error) {
      return [];
    }
  }

  private mapStatus(status: number): 'OPEN' | 'LOCKED' | 'SETTLED' | 'CANCELLED' {
    switch (status) {
      case 0: return 'OPEN';
      case 1: return 'LOCKED';
      case 2: return 'SETTLED';
      case 3: return 'CANCELLED';
      default: return 'OPEN';
    }
  }

  private async queryActiveEvents(): Promise<string[]> {
    // 实现查询活跃事件的逻辑
    // 可以通过事件日志或其他方式获取
    return [];
  }
}
```

### 3. 事件监听和实时更新

```typescript
// services/eventListener.ts
import { ethers } from 'ethers';
import { Web3Service } from './web3';

export class EventListener {
  private listeners: Map<string, Function[]> = new Map();

  constructor(private web3Service: Web3Service) {
    this.setupEventListeners();
  }

  // 设置合约事件监听
  private setupEventListeners() {
    // 监听 PredictionRouter 事件
    this.web3Service.predictionRouter.on('CreateAndBet', (user, eventAddress, position, amount, token) => {
      this.emit('betPlaced', { user, eventAddress, position, amount, token });
    });

    this.web3Service.predictionRouter.on('IntelligentBet', (user, eventAddress, position, amount, token, aiRequestId) => {
      this.emit('aiBetPlaced', { user, eventAddress, position, amount, token, aiRequestId });
    });

    this.web3Service.predictionRouter.on('BatchBet', (user, eventAddresses, positions, amounts, tokens) => {
      this.emit('batchBetPlaced', { user, eventAddresses, positions, amounts, tokens });
    });

    this.web3Service.predictionRouter.on('EventSettled', (eventAddress, winningPosition) => {
      this.emit('eventSettled', { eventAddress, winningPosition });
    });

    this.web3Service.predictionRouter.on('WinningsClaimed', (user, eventAddress, amount) => {
      this.emit('winningsClaimed', { user, eventAddress, amount });
    });

    // 监听价格预言机事件
    this.web3Service.priceOracle.on('PriceUpdated', (token, price, timestamp) => {
      this.emit('priceUpdated', { token, price, timestamp });
    });

    // 监听账户变化
    if (window.ethereum) {
      window.ethereum.on('accountsChanged', (accounts) => {
        this.emit('accountChanged', { accounts });
      });

      window.ethereum.on('chainChanged', (chainId) => {
        this.emit('chainChanged', { chainId });
      });
    }
  }

  // 注册事件监听器
  on(event: string, callback: Function) {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, []);
    }
    this.listeners.get(event)!.push(callback);
  }

  // 移除事件监听器
  off(event: string, callback: Function) {
    const callbacks = this.listeners.get(event);
    if (callbacks) {
      const index = callbacks.indexOf(callback);
      if (index > -1) {
        callbacks.splice(index, 1);
      }
    }
  }

  // 触发事件
  private emit(event: string, data: any) {
    const callbacks = this.listeners.get(event);
    if (callbacks) {
      callbacks.forEach(callback => {
        try {
          callback(data);
        } catch (error) {
          console.error(`Event listener error for ${event}:`, error);
        }
      });
    }
  }

  // 清理所有监听器
  cleanup() {
    this.web3Service.predictionRouter.removeAllListeners();
    this.web3Service.priceOracle.removeAllListeners();
    this.listeners.clear();
  }
}
```

### 4. React 集成示例

```typescript
// hooks/useContract.ts
import { useState, useEffect, useCallback } from 'react';
import { Web3Service } from '../services/web3';
import { PredictionService } from '../services/predictionService';
import { EventService } from '../services/eventService';
import { EventListener } from '../services/eventListener';

export const useContract = () => {
  const [web3Service, setWeb3Service] = useState<Web3Service | null>(null);
  const [predictionService, setPredictionService] = useState<PredictionService | null>(null);
  const [eventService, setEventService] = useState<EventService | null>(null);
  const [eventListener, setEventListener] = useState<EventListener | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // 初始化服务
  useEffect(() => {
    const initializeServices = async () => {
      try {
        const web3 = new Web3Service();
        await web3.initialize();

        const prediction = new PredictionService(web3);
        const events = new EventService(web3);
        const listener = new EventListener(web3);

        setWeb3Service(web3);
        setPredictionService(prediction);
        setEventService(events);
        setEventListener(listener);
        setIsLoading(false);
      } catch (err) {
        setError(err.message);
        setIsLoading(false);
      }
    };

    initializeServices();
  }, []);

  // 清理服务
  useEffect(() => {
    return () => {
      if (eventListener) {
        eventListener.cleanup();
      }
    };
  }, [eventListener]);

  return {
    web3Service,
    predictionService,
    eventService,
    eventListener,
    isLoading,
    error,
  };
};

// hooks/useEvents.ts
import { useState, useEffect } from 'react';
import { useContract } from './useContract';
import { EventInfo } from '../services/eventService';

export const useEvents = () => {
  const { eventService, eventListener } = useContract();
  const [events, setEvents] = useState<EventInfo[]>([]);
  const [userEvents, setUserEvents] = useState<EventInfo[]>([]);
  const [loading, setLoading] = useState(true);

  // 加载所有活跃事件
  const loadEvents = async () => {
    if (!eventService) return;

    try {
      setLoading(true);
      const activeEvents = await eventService.getActiveEvents();
      setEvents(activeEvents);
    } catch (error) {
      console.error('加载事件失败:', error);
    } finally {
      setLoading(false);
    }
  };

  // 加载用户事件
  const loadUserEvents = async () => {
    if (!eventService) return;

    try {
      const userActiveEvents = await eventService.getUserActiveEvents();
      setUserEvents(userActiveEvents);
    } catch (error) {
      console.error('加载用户事件失败:', error);
    }
  };

  // 初始加载
  useEffect(() => {
    loadEvents();
    loadUserEvents();
  }, [eventService]);

  // 监听事件变化
  useEffect(() => {
    if (!eventListener) return;

    const handleBetPlaced = () => {
      loadEvents();
      loadUserEvents();
    };

    const handleEventSettled = () => {
      loadEvents();
      loadUserEvents();
    };

    eventListener.on('betPlaced', handleBetPlaced);
    eventListener.on('batchBetPlaced', handleBetPlaced);
    eventListener.on('eventSettled', handleEventSettled);

    return () => {
      eventListener.off('betPlaced', handleBetPlaced);
      eventListener.off('batchBetPlaced', handleBetPlaced);
      eventListener.off('eventSettled', handleEventSettled);
    };
  }, [eventListener]);

  return {
    events,
    userEvents,
    loading,
    refresh: () => {
      loadEvents();
      loadUserEvents();
    },
  };
};
```

---

## 🔧 后端与合约交互

### 1. Node.js 服务架构

```javascript
// services/contractService.js
const { ethers } = require('ethers');
const { PredictionRouterABI } = require('./abis/PredictionRouter');
const { BinaryOptionABI } = require('./abis/BinaryOption');

class ContractService {
  constructor() {
    this.provider = null;
    this.signer = null;
    this.contracts = {};
    this.initialize();
  }

  async initialize() {
    // 初始化提供者
    this.provider = new ethers.JsonRpcProvider(process.env.RPC_URL);

    // 初始化签名者（用于管理操作）
    if (process.env.PRIVATE_KEY) {
      this.signer = new ethers.Wallet(process.env.PRIVATE_KEY, this.provider);
    }

    // 初始化合约实例
    this.contracts.predictionRouter = new ethers.Contract(
      process.env.PREDICTION_ROUTER_ADDRESS,
      PredictionRouterABI,
      this.signer || this.provider
    );

    this.contracts.priceOracle = new ethers.Contract(
      process.env.PRICE_ORACLE_ADDRESS,
      PriceOracleABI,
      this.signer || this.provider
    );
  }

  // 获取合约实例
  getContract(name) {
    return this.contracts[name];
  }

  // 监听合约事件
  startEventListener(eventName, callback, fromBlock = 'latest') {
    const contract = this.getContract('predictionRouter');
    contract.on(eventName, callback, { fromBlock });
  }

  // 停止监听事件
  stopEventListener(eventName) {
    const contract = this.getContract('predictionRouter');
    contract.removeAllListeners(eventName);
  }

  // 查询历史事件
  async queryEvents(eventName, fromBlock = 0, toBlock = 'latest') {
    const contract = this.getContract('predictionRouter');
    const filter = contract.filters[eventName]();
    const events = await contract.queryFilter(filter, fromBlock, toBlock);
    return events;
  }

  // 批量查询事件信息
  async batchGetEventInfo(eventAddresses) {
    const promises = eventAddresses.map(address => {
      const contract = new ethers.Contract(address, BinaryOptionABI, this.provider);
      return contract.getEventInfo();
    });

    const results = await Promise.all(promises);
    return eventAddresses.map((address, index) => ({
      address,
      info: results[index],
    }));
  }

  // 获取系统状态
  async getSystemStatus() {
    try {
      const [paused, riskLevel, totalUsers] = await Promise.all([
        this.getContract('accessController').paused(),
        this.getContract('riskManager').getSystemRiskLevel(),
        this.getContract('predictionRouter').getTotalUsers(),
      ]);

      return {
        isPaused: paused,
        riskLevel,
        totalUsers: Number(totalUsers),
      };
    } catch (error) {
      throw new Error(`获取系统状态失败: ${error.message}`);
    }
  }
}

module.exports = ContractService;
```

### 2. 数据同步服务

```javascript
// services/dataSyncService.js
const ContractService = require('./contractService');
const Event = require('../models/Event');
const UserBet = require('../models/UserBet');
const PriceData = require('../models/PriceData');

class DataSyncService {
  constructor() {
    this.contractService = new ContractService();
    this.isRunning = false;
    this.syncInterval = null;
  }

  // 启动数据同步
  async startSync(intervalMinutes = 1) {
    if (this.isRunning) {
      console.log('数据同步已在运行中');
      return;
    }

    this.isRunning = true;
    console.log('启动数据同步服务...');

    // 立即执行一次同步
    await this.syncAllData();

    // 设置定时同步
    this.syncInterval = setInterval(async () => {
      try {
        await this.syncAllData();
      } catch (error) {
        console.error('定时同步失败:', error);
      }
    }, intervalMinutes * 60 * 1000);

    // 启动实时事件监听
    this.startEventListeners();
  }

  // 停止数据同步
  stopSync() {
    if (this.syncInterval) {
      clearInterval(this.syncInterval);
      this.syncInterval = null;
    }

    this.stopEventListeners();
    this.isRunning = false;
    console.log('数据同步服务已停止');
  }

  // 同步所有数据
  async syncAllData() {
    console.log('开始同步数据...');
    const startTime = Date.now();

    try {
      await Promise.all([
        this.syncEvents(),
        this.syncPriceData(),
        this.updateSettledEvents(),
      ]);

      const duration = Date.now() - startTime;
      console.log(`数据同步完成，耗时: ${duration}ms`);
    } catch (error) {
      console.error('数据同步失败:', error);
      throw error;
    }
  }

  // 同步事件数据
  async syncEvents() {
    try {
      // 获取最新的事件创建事件
      const lastSyncBlock = await this.getLastSyncBlock('EventCreated');
      const currentBlock = await this.contractService.provider.getBlockNumber();

      const events = await this.contractService.queryEvents(
        'EventCreated',
        lastSyncBlock + 1,
        currentBlock
      );

      for (const event of events) {
        await this.processEventCreated(event);
      }

      // 更新最后同步区块
      await this.updateLastSyncBlock('EventCreated', currentBlock);
    } catch (error) {
      console.error('同步事件数据失败:', error);
    }
  }

  // 处理事件创建
  async processEventCreated(event) {
    const { eventAddress, creator, token, targetPrice, duration, description } = event.args;

    // 检查事件是否已存在
    const existingEvent = await Event.findOne({ address: eventAddress });
    if (existingEvent) return;

    // 获取详细的事件信息
    const eventContract = new ethers.Contract(
      eventAddress,
      BinaryOptionABI,
      this.contractService.provider
    );

    const eventInfo = await eventContract.getEventInfo();

    // 保存事件到数据库
    const newEvent = new Event({
      address: eventAddress,
      creator,
      token,
      targetPrice: ethers.formatEther(targetPrice),
      duration: Number(duration),
      description,
      startTime: Number(eventInfo.startTime),
      endTime: Number(eventInfo.endTime),
      status: this.mapStatus(Number(eventInfo.status)),
      createdAt: new Date(event.args.timestamp * 1000),
      updatedAt: new Date(),
    });

    await newEvent.save();
    console.log(`新事件已保存: ${eventAddress}`);
  }

  // 同步价格数据
  async syncPriceData() {
    try {
      const supportedTokens = await this.getSupportedTokens();
      const currentBlock = await this.contractService.provider.getBlockNumber();

      for (const token of supportedTokens) {
        await this.syncTokenPriceData(token, currentBlock);
      }
    } catch (error) {
      console.error('同步价格数据失败:', error);
    }
  }

  // 同步特定代币的价格数据
  async syncTokenPriceData(tokenAddress, currentBlock) {
    try {
      // 获取最新价格更新事件
      const lastSyncBlock = await this.getLastSyncBlock(`PriceUpdated_${tokenAddress}`);
      const events = await this.contractService.queryEvents(
        'PriceUpdated',
        lastSyncBlock + 1,
        currentBlock
      ).filter(event => event.args.token === tokenAddress);

      for (const event of events) {
        const { token, price, timestamp } = event.args;

        // 检查是否已存在相同时间戳的价格数据
        const existingPrice = await PriceData.findOne({
          token,
          timestamp: Number(timestamp),
        });

        if (!existingPrice) {
          const priceData = new PriceData({
            token,
            price: ethers.formatEther(price),
            timestamp: Number(timestamp),
            blockNumber: event.blockNumber,
            createdAt: new Date(Number(timestamp) * 1000),
          });

          await priceData.save();
        }
      }

      // 更新最后同步区块
      await this.updateLastSyncBlock(`PriceUpdated_${tokenAddress}`, currentBlock);
    } catch (error) {
      console.error(`同步代币 ${tokenAddress} 价格数据失败:`, error);
    }
  }

  // 更新已结算事件
  async updateSettledEvents() {
    try {
      // 查找所有未结算但已过期的事件
      const expiredEvents = await Event.find({
        status: 'OPEN',
        endTime: { $lt: Date.now() / 1000 },
      });

      for (const event of expiredEvents) {
        await this.checkAndSettleEvent(event);
      }
    } catch (error) {
      console.error('更新已结算事件失败:', error);
    }
  }

  // 检查并结算事件
  async checkAndSettleEvent(event) {
    try {
      const eventContract = new ethers.Contract(
        event.address,
        BinaryOptionABI,
        this.contractService.signer
      );

      // 检查事件是否可以结算
      const canSettle = await eventContract.canSettle();
      if (!canSettle) return;

      // 执行结算
      const tx = await eventContract.settle();
      await tx.wait();

      // 更新数据库状态
      event.status = 'SETTLED';
      event.updatedAt = new Date();
      await event.save();

      console.log(`事件已结算: ${event.address}`);
    } catch (error) {
      console.error(`结算事件 ${event.address} 失败:`, error);
    }
  }

  // 启动事件监听器
  startEventListeners() {
    // 监听下注事件
    this.contractService.startEventListener('BetPlaced', async (event) => {
      await this.processBetPlaced(event);
    });

    // 监听事件结算
    this.contractService.startEventListener('EventSettled', async (event) => {
      await this.processEventSettled(event);
    });

    // 监听奖金领取
    this.contractService.startEventListener('WinningsClaimed', async (event) => {
      await this.processWinningsClaimed(event);
    });
  }

  // 处理下注事件
  async processBetPlaced(event) {
    const { user, position, amount, timestamp } = event.args;

    try {
      const userBet = new UserBet({
        user,
        eventAddress: event.address,
        position: position === 0 ? 'YES' : 'NO',
        amount: ethers.formatEther(amount),
        timestamp: Number(timestamp),
        createdAt: new Date(Number(timestamp) * 1000),
      });

      await userBet.save();
      console.log(`用户下注已记录: ${user} 在 ${event.address}`);
    } catch (error) {
      console.error('记录下注事件失败:', error);
    }
  }

  // 处理事件结算
  async processEventSettled(event) {
    const { winningPosition } = event.args;

    try {
      await Event.updateOne(
        { address: event.address },
        {
          status: 'SETTLED',
          winningPosition: winningPosition === 0 ? 'YES' : 'NO',
          updatedAt: new Date(),
        }
      );

      // 计算所有用户的奖金
      await this.calculateUserWinnings(event.address, winningPosition);

      console.log(`事件结算已更新: ${event.address}`);
    } catch (error) {
      console.error('更新事件结算失败:', error);
    }
  }

  // 计算用户奖金
  async calculateUserWinnings(eventAddress, winningPosition) {
    try {
      const eventContract = new ethers.Contract(
        eventAddress,
        BinaryOptionABI,
        this.contractService.provider
      );

      const userBets = await UserBet.find({ eventAddress, claimed: false });

      for (const bet of userBets) {
        if ((bet.position === 'YES' && winningPosition === 0) ||
            (bet.position === 'NO' && winningPosition === 1)) {

          const winnings = await eventContract.getUserWinnings(bet.user);

          await UserBet.updateOne(
            { _id: bet._id },
            {
              winnings: ethers.formatEther(winnings),
              won: true,
            }
          );
        }
      }
    } catch (error) {
      console.error(`计算事件 ${eventAddress} 用户奖金失败:`, error);
    }
  }

  // 辅助方法
  async getLastSyncBlock(eventType) {
    // 从数据库或缓存获取最后同步的区块号
    return 0; // 简化实现
  }

  async updateLastSyncBlock(eventType, blockNumber) {
    // 保存最后同步的区块号
  }

  async getSupportedTokens() {
    // 获取支持的代币列表
    return ['0x...', '0x...']; // 示例地址
  }

  mapStatus(status) {
    switch (status) {
      case 0: return 'OPEN';
      case 1: return 'LOCKED';
      case 2: return 'SETTLED';
      case 3: return 'CANCELLED';
      default: return 'OPEN';
    }
  }

  stopEventListeners() {
    // 停止所有事件监听器
    this.contractService.stopEventListener('BetPlaced');
    this.contractService.stopEventListener('EventSettled');
    this.contractService.stopEventListener('WinningsClaimed');
  }
}

module.exports = DataSyncService;
```

### 3. 监控和风险管理

```javascript
// services/monitoringService.js
const ContractService = require('./contractService');

class MonitoringService {
  constructor() {
    this.contractService = new ContractService();
    this.alerts = [];
    this.thresholds = {
      maxGasPrice: 100, // gwei
      maxPendingTxs: 100,
      minOraclePriceAge: 300, // 5分钟
      maxPoolSize: ethers.parseEther('1000000'), // 1M
      maxUserExposure: ethers.parseEther('50000'), // 50K
    };
  }

  // 启动监控服务
  async startMonitoring(intervalSeconds = 30) {
    console.log('启动监控服务...');

    // 立即执行一次检查
    await this.performHealthCheck();

    // 设置定时检查
    setInterval(async () => {
      await this.performHealthCheck();
    }, intervalSeconds * 1000);
  }

  // 执行健康检查
  async performHealthCheck() {
    try {
      await Promise.all([
        this.checkNetworkHealth(),
        this.checkOracleHealth(),
        this.checkRiskMetrics(),
        this.checkContractHealth(),
      ]);
    } catch (error) {
      console.error('健康检查失败:', error);
    }
  }

  // 检查网络健康状态
  async checkNetworkHealth() {
    try {
      const [blockNumber, gasPrice] = await Promise.all([
        this.contractService.provider.getBlockNumber(),
        this.contractService.provider.getFeeData(),
      ]);

      const gasPriceGwei = Number(ethers.formatUnits(gasPrice.gasPrice || 0, 'gwei'));

      if (gasPriceGwei > this.thresholds.maxGasPrice) {
        await this.createAlert('HIGH_GAS_PRICE', {
          currentPrice: gasPriceGwei,
          threshold: this.thresholds.maxGasPrice,
          severity: 'WARNING',
        });
      }

      // 检查区块同步
      const now = Math.floor(Date.now() / 1000);
      const block = await this.contractService.provider.getBlock(blockNumber);
      const blockAge = now - block.timestamp;

      if (blockAge > 60) { // 区块超过1分钟
        await this.createAlert('BLOCK_SYNC_DELAY', {
          blockAge,
          severity: 'ERROR',
        });
      }
    } catch (error) {
      await this.createAlert('NETWORK_ERROR', { error: error.message });
    }
  }

  // 检查预言机健康状态
  async checkOracleHealth() {
    try {
      const supportedTokens = await this.getSupportedTokens();

      for (const token of supportedTokens) {
        const priceData = await this.contractService.contracts.priceOracle.getLatestPrice(token);
        const priceAge = Math.floor(Date.now() / 1000) - Number(priceData.timestamp);

        if (priceAge > this.thresholds.minOraclePriceAge) {
          await this.createAlert('ORACLE_PRICE_STALE', {
            token,
            age: priceAge,
            threshold: this.thresholds.minOraclePriceAge,
            severity: 'WARNING',
          });
        }
      }
    } catch (error) {
      await this.createAlert('ORACLE_ERROR', { error: error.message });
    }
  }

  // 检查风险指标
  async checkRiskMetrics() {
    try {
      const riskManager = this.contractService.getContract('riskManager');
      const metrics = await riskManager.getSystemMetrics();

      // 检查总风险敞口
      if (metrics.totalExposure > this.thresholds.maxUserExposure) {
        await this.createAlert('HIGH_SYSTEM_EXPOSURE', {
          current: ethers.formatEther(metrics.totalExposure),
          threshold: ethers.formatEther(this.thresholds.maxUserExposure),
          severity: 'WARNING',
        });
      }

      // 检查活跃事件数量
      if (metrics.activeEvents > 1000) {
        await this.createAlert('HIGH_ACTIVE_EVENTS', {
          count: metrics.activeEvents,
          severity: 'INFO',
        });
      }

      // 检查熔断器状态
      if (metrics.circuitBreakerTriggered) {
        await this.createAlert('CIRCUIT_BREAKER_TRIGGERED', {
          reason: metrics.circuitBreakerReason,
          severity: 'CRITICAL',
        });
      }
    } catch (error) {
      await this.createAlert('RISK_METRICS_ERROR', { error: error.message });
    }
  }

  // 检查合约健康状态
  async checkContractHealth() {
    try {
      const accessController = this.contractService.getContract('accessController');
      const isPaused = await accessController.paused();

      if (isPaused) {
        await this.createAlert('SYSTEM_PAUSED', {
          severity: 'CRITICAL',
        });
      }

      // 检查合约余额
      const treasury = this.contractService.getContract('treasury');
      const balance = await this.contractService.provider.getBalance(treasury.target);

      if (balance < ethers.parseEther('10')) { // 余额少于10 ETH
        await this.createAlert('LOW_TREASURY_BALANCE', {
          balance: ethers.formatEther(balance),
          severity: 'WARNING',
        });
      }
    } catch (error) {
      await this.createAlert('CONTRACT_HEALTH_ERROR', { error: error.message });
    }
  }

  // 创建警报
  async createAlert(type, data) {
    const alert = {
      id: Date.now(),
      type,
      data,
      timestamp: new Date(),
      resolved: false,
    };

    this.alerts.push(alert);

    // 限制警报数量
    if (this.alerts.length > 1000) {
      this.alerts = this.alerts.slice(-500);
    }

    // 发送通知
    await this.sendNotification(alert);

    console.warn(`警报 [${type}]:`, data);
  }

  // 发送通知
  async sendNotification(alert) {
    try {
      // 根据严重程度决定通知方式
      switch (alert.data.severity) {
        case 'CRITICAL':
          await this.sendEmailNotification(alert);
          await this.sendSlackNotification(alert);
          break;
        case 'ERROR':
          await this.sendSlackNotification(alert);
          break;
        case 'WARNING':
          // 仅记录日志
          break;
      }
    } catch (error) {
      console.error('发送通知失败:', error);
    }
  }

  // 发送邮件通知
  async sendEmailNotification(alert) {
    // 实现邮件发送逻辑
    console.log('发送邮件通知:', alert);
  }

  // 发送 Slack 通知
  async sendSlackNotification(alert) {
    // 实现 Slack 通知逻辑
    console.log('发送 Slack 通知:', alert);
  }

  // 获取支持的代币
  async getSupportedTokens() {
    // 返回支持的代币列表
    return ['0x...', '0x...'];
  }

  // 获取警报列表
  getAlerts(limit = 100) {
    return this.alerts.slice(-limit);
  }

  // 解决警报
  resolveAlert(alertId) {
    const alert = this.alerts.find(a => a.id === alertId);
    if (alert) {
      alert.resolved = true;
      alert.resolvedAt = new Date();
    }
  }
}

module.exports = MonitoringService;
```

### 4. API 路由示例

```javascript
// routes/events.js
const express = require('express');
const router = express.Router();
const ContractService = require('../services/contractService');
const DataSyncService = require('../services/dataSyncService');

const contractService = new ContractService();
const dataSyncService = new DataSyncService();

// 获取活跃事件列表
router.get('/active', async (req, res) => {
  try {
    const events = await Event.find({
      status: { $in: ['OPEN', 'LOCKED'] },
    }).sort({ createdAt: -1 });

    res.json({
      success: true,
      data: events,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// 获取事件详情
router.get('/:address', async (req, res) => {
  try {
    const { address } = req.params;

    // 从数据库获取基本信息
    const event = await Event.findOne({ address });
    if (!event) {
      return res.status(404).json({
        success: false,
        error: '事件不存在',
      });
    }

    // 从合约获取实时信息
    const eventContract = new ethers.Contract(
      address,
      BinaryOptionABI,
      contractService.provider
    );

    const [currentOdds, yesPool, noPool] = await Promise.all([
      eventContract.getCurrentOdds(),
      eventContract.yesPool(),
      eventContract.noPool(),
    ]);

    res.json({
      success: true,
      data: {
        ...event.toObject(),
        yesPool: ethers.formatEther(yesPool),
        noPool: ethers.formatEther(noPool),
        yesOdds: ethers.formatEther(currentOdds[0]),
        noOdds: ethers.formatEther(currentOdds[1]),
        totalPool: ethers.formatEther(yesPool + noPool),
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// 获取用户在事件中的下注
router.get('/:address/bets/:userAddress', async (req, res) => {
  try {
    const { address, userAddress } = req.params;

    const bets = await UserBet.find({
      eventAddress: address,
      user: userAddress,
    }).sort({ createdAt: -1 });

    res.json({
      success: true,
      data: bets,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// 获取事件历史记录
router.get('/:address/history', async (req, res) => {
  try {
    const { address } = req.params;
    const { limit = 100 } = req.query;

    // 从合约获取事件历史
    const events = await contractService.queryEvents('BetPlaced', 0, 'latest')
      .filter(event => event.address === address)
      .slice(0, parseInt(limit));

    res.json({
      success: true,
      data: events.map(event => ({
        transactionHash: event.transactionHash,
        blockNumber: event.blockNumber,
        user: event.args.user,
        position: event.args.position === 0 ? 'YES' : 'NO',
        amount: ethers.formatEther(event.args.amount),
        timestamp: Number(event.args.timestamp),
      })),
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// 手动触发事件结算
router.post('/:address/settle', async (req, res) => {
  try {
    const { address } = req.params;

    const eventContract = new ethers.Contract(
      address,
      BinaryOptionABI,
      contractService.signer
    );

    const tx = await eventContract.settle();
    const receipt = await tx.wait();

    res.json({
      success: true,
      data: {
        transactionHash: receipt.hash,
        blockNumber: receipt.blockNumber,
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

module.exports = router;
```

---

## 📋 合约 ABI 和事件监听

### ABI 文件结构

```typescript
// abi/index.ts
export { default as PredictionRouterABI } from './PredictionRouter.json';
export { default as BinaryOptionABI } from './BinaryOption.json';
export { default as PriceOracleABI } from './PriceOracle.json';
export { default as RiskManagerABI } from './RiskManager.json';
export { default as TreasuryABI } from './Treasury.json';
export { default as AccessControllerABI } from './AccessController.json';
export { default as X404PaymentProcessorABI } from './X404PaymentProcessor.json';
```

### 事件监听配置

```typescript
// config/events.ts
export const EVENT_CONFIGS = {
  BetPlaced: {
    callback: 'handleBetPlaced',
    store: true,
    notify: true,
  },
  EventSettled: {
    callback: 'handleEventSettled',
    store: true,
    notify: true,
  },
  WinningsClaimed: {
    callback: 'handleWinningsClaimed',
    store: true,
    notify: false,
  },
  PriceUpdated: {
    callback: 'handlePriceUpdated',
    store: true,
    notify: false,
  },
  CircuitBreakerTriggered: {
    callback: 'handleCircuitBreaker',
    store: true,
    notify: true,
    severity: 'CRITICAL',
  },
};
```

---

## 🔒 安全最佳实践

### 前端安全

1. **私钥管理**
   ```typescript
   // 永远不要在前端存储私钥
   // 只通过 MetaMask 等钱包应用进行签名操作
   const signature = await signer.signMessage(message);
   ```

2. **输入验证**
   ```typescript
   function validateBetAmount(amount: string): boolean {
     const num = parseFloat(amount);
     return !isNaN(num) && num >= 0.001 && num <= 1000;
   }
   ```

3. **交易确认**
   ```typescript
   const tx = await contract.placeBet(amount);
   // 等待至少1个确认
   await tx.wait(1);
   ```

### 后端安全

1. **环境变量保护**
   ```javascript
   // 使用 .env 文件存储敏感信息
   const privateKey = process.env.PRIVATE_KEY;
   if (!privateKey) {
     throw new Error('私钥未配置');
   }
   ```

2. **访问控制**
   ```javascript
   // 实现角色基础的访问控制
   function requireRole(userRole) {
     return (req, res, next) => {
       if (!req.user.roles.includes(userRole)) {
         return res.status(403).json({ error: '权限不足' });
       }
       next();
     };
   }
   ```

3. **交易重放保护**
   ```javascript
   // 使用 nonce 防止重放攻击
   const nonce = Date.now() + Math.random();
   const message = `${nonce}${action}${userAddress}`;
   const signature = await signer.signMessage(message);
   ```

---

## ⚡ 性能优化建议

### 前端优化

1. **批量查询**
   ```typescript
   // 使用 multicall 减少请求次数
   const results = await multicall([
     contract.balanceOf(address1),
     contract.balanceOf(address2),
     contract.totalSupply(),
   ]);
   ```

2. **缓存策略**
   ```typescript
   // 实现智能缓存
   const cache = new Map();
   const CACHE_TTL = 30000; // 30秒

   async function getCachedData(key) {
     const cached = cache.get(key);
     if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
       return cached.data;
     }

     const data = await fetchData(key);
     cache.set(key, { data, timestamp: Date.now() });
     return data;
   }
   ```

3. **事件分页**
   ```typescript
   // 实现分页加载
   async function getEvents(page = 1, limit = 20) {
     const skip = (page - 1) * limit;
     return await Event.find()
       .sort({ createdAt: -1 })
       .skip(skip)
       .limit(limit);
   }
   ```

### 后端优化

1. **数据库索引**
   ```javascript
   // 为常用查询字段添加索引
   EventSchema.index({ status: 1, createdAt: -1 });
   UserBetSchema.index({ user: 1, eventAddress: 1 });
   PriceDataSchema.index({ token: 1, timestamp: -1 });
   ```

2. **连接池**
   ```javascript
   // MongoDB 连接池配置
   mongoose.connect(process.env.MONGODB_URI, {
     maxPoolSize: 10,
     serverSelectionTimeoutMS: 5000,
     socketTimeoutMS: 45000,
   });
   ```

3. **事件处理优化**
   ```javascript
   // 使用队列处理事件
   const eventQueue = new Queue('event processing');

   eventQueue.process(async (job) => {
     const { eventType, data } = job.data;
     await processEvent(eventType, data);
   });
   ```

---

这份详细的交互指南涵盖了前后端与 memeX 智能合约系统的所有交互场景，包括代码示例、最佳实践和性能优化建议。开发者可以根据具体需求选择相应的实现方式。