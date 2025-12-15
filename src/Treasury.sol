// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title Treasury
 * @dev 财库合约，管理平台资金和收入分配
 */
contract Treasury is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // 收入分配比例 (基点)
    struct RevenueSplit {
        uint256 platformReserve; // 平台储备
        uint256 liquidityProviders; // 流动性提供者
        uint256 aiProviders; // AI服务提供者
        uint256 teamRewards; // 团队奖励
        uint256 treasury; // 财库
    }

    // 资金池配置
    struct PoolConfig {
        address token; // 代币地址
        uint256 totalCollected; // 总收取
        uint256 totalDistributed; // 总分配
        uint256 reserveAmount; // 储备金额
        uint256 lastDistribution; // 最后分配时间
        uint256 distributionPeriod; // 分配周期 (秒)
        bool active; // 是否激活
    }

    // 收入记录
    struct IncomeRecord {
        uint256 amount;
        uint256 timestamp;
        string source; // 收入来源
        address token; // 代币地址
        bool distributed; // 是否已分配
    }

    // 分配记录
    struct DistributionRecord {
        uint256 amount;
        uint256 timestamp;
        address recipient;
        string category;
        address token;
    }

    // 状态变量
    RevenueSplit public revenueSplit;
    mapping(address => PoolConfig) public poolConfigs;
    mapping(address => IncomeRecord[]) public incomeHistory;
    mapping(address => DistributionRecord[]) public distributionHistory;

    // 支持的代币
    address[] public supportedTokens;
    mapping(address => bool) public isTokenSupported;

    // 接收地址
    address public platformReserveAddress;
    address public liquidityProviderAddress;
    address public aiProviderAddress;
    address public teamRewardAddress;

    // 统计数据
    mapping(address => uint256) public totalCollectedByToken;
    mapping(address => uint256) public totalDistributedByToken;
    uint256 public totalCollectedAllTokens;
    uint256 public totalDistributedAllTokens;
    uint256 public distributionCount;

    // 紧急提取
    mapping(address => uint256) public emergencyWithdrawAmount;
    bool public emergencyMode;

    // Internal check functions
    function _checkValidToken(address token) private view {
        require(isTokenSupported[token], TokenNotSupported());
    }

    function _checkNotEmergency() private view {
        require(!emergencyMode, EmergencyModeActive());
    }

    function _checkEmergencyMode() private view {
        require(emergencyMode, EmergencyModeNotActive());
    }

    // Modifiers
    modifier onlyValidToken(address token) {
        _checkValidToken(token);
        _;
    }

    modifier onlyNotEmergency() {
        _checkNotEmergency();
        _;
    }

    modifier onlyEmergencyMode() {
        _checkEmergencyMode();
        _;
    }

    constructor(address[] memory _supportedTokens) Ownable(msg.sender) {
        require(_supportedTokens.length > 0, Errors.EmptyArray());

        // 初始化支持的代币
        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            if (_supportedTokens[i] != address(0)) {
                supportedTokens.push(_supportedTokens[i]);
                isTokenSupported[_supportedTokens[i]] = true;
                poolConfigs[_supportedTokens[i]] = PoolConfig({
                    token: _supportedTokens[i],
                    totalCollected: 0,
                    totalDistributed: 0,
                    reserveAmount: 0,
                    lastDistribution: 0,
                    distributionPeriod: 86400, // 24小时
                    active: true
                });
            }
        }

        // 初始化收入分配比例
        revenueSplit = RevenueSplit({
            platformReserve: 3000, // 30%
            liquidityProviders: 2500, // 25%
            aiProviders: 2500, // 25%
            teamRewards: 1000, // 10%
            treasury: 1000 // 10%
        });

        // 设置默认接收地址 (部署后需要更新)
        platformReserveAddress = msg.sender;
        liquidityProviderAddress = msg.sender;
        aiProviderAddress = msg.sender;
        teamRewardAddress = msg.sender;
    }

    /**
     * @dev 收取费用
     */
    function collectFee(
        address token,
        uint256 amount,
        string calldata source
    ) external nonReentrant onlyNotEmergency onlyValidToken(token) {
        require(amount > 0, Errors.InvalidAmount());
        require(bytes(source).length > 0, Errors.EmptyString());

        // 转账到财库
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // 更新统计
        PoolConfig storage pool = poolConfigs[token];
        pool.totalCollected += amount;
        totalCollectedByToken[token] += amount;
        totalCollectedAllTokens += amount;

        // 记录收入
        incomeHistory[token].push(
            IncomeRecord({
                amount: amount,
                timestamp: block.timestamp,
                source: source,
                token: token,
                distributed: false
            })
        );

        // 检查是否需要自动分配
        if (
            block.timestamp >= pool.lastDistribution + pool.distributionPeriod
        ) {
            _distributeRevenue(token);
        }

        emit Events.FeesCollected(amount, block.timestamp);
    }

    /**
     * @dev 分配收入
     */
    function distributeRevenue(
        address token
    ) external nonReentrant onlyNotEmergency onlyValidToken(token) {
        _distributeRevenue(token);
    }

    /**
     * @dev 批量分配收入
     */
    function batchDistributeRevenue(
        address[] calldata tokens
    ) external nonReentrant onlyNotEmergency {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (isTokenSupported[tokens[i]]) {
                try this.distributeRevenue(tokens[i]) {
                    // 成功分配
                } catch {
                    // 记录失败的分配
                    emit DistributionFailed(tokens[i], "Distribution failed");
                }
            }
        }
    }

    /**
     * @dev 提取资金
     */
    function withdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyOwner onlyNotEmergency onlyValidToken(token) {
        require(recipient != address(0), Errors.ZeroAddress());
        require(amount > 0, Errors.InvalidAmount());

        PoolConfig storage pool = poolConfigs[token];
        require(pool.reserveAmount >= amount, Errors.InsufficientFunds());

        // 更新储备
        pool.reserveAmount -= amount;

        // 转账
        IERC20(token).safeTransfer(recipient, amount);

        emit Events.FundsWithdrawn(recipient, amount, block.timestamp);
    }

    /**
     * @dev 紧急提取
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyOwner onlyEmergencyMode onlyValidToken(token) {
        require(recipient != address(0), Errors.ZeroAddress());
        require(amount > 0, Errors.InvalidAmount());

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance >= amount, Errors.InsufficientBalance());
        require(
            emergencyWithdrawAmount[token] >= amount,
            InsufficientEmergencyAllowance()
        );

        // 更新紧急提取限额
        emergencyWithdrawAmount[token] -= amount;

        // 转账
        IERC20(token).safeTransfer(recipient, amount);

        emit EmergencyWithdrawal(recipient, token, amount, block.timestamp);
    }

    /**
     * @dev 设置收入分配比例
     */
    function setRevenueSplit(
        RevenueSplit calldata newSplit
    ) external onlyOwner {
        uint256 total = newSplit.platformReserve +
            newSplit.liquidityProviders +
            newSplit.aiProviders +
            newSplit.teamRewards +
            newSplit.treasury;

        require(total == 10000, InvalidRevenueSplit()); // 总和必须为100%

        revenueSplit = newSplit;
        emit RevenueSplitUpdated(newSplit);
    }

    /**
     * @dev 设置接收地址
     */
    function setRecipientAddresses(
        address _platformReserve,
        address _liquidityProvider,
        address _aiProvider,
        address _teamReward
    ) external onlyOwner {
        require(_platformReserve != address(0), Errors.ZeroAddress());
        require(_liquidityProvider != address(0), Errors.ZeroAddress());
        require(_aiProvider != address(0), Errors.ZeroAddress());
        require(_teamReward != address(0), Errors.ZeroAddress());

        platformReserveAddress = _platformReserve;
        liquidityProviderAddress = _liquidityProvider;
        aiProviderAddress = _aiProvider;
        teamRewardAddress = _teamReward;
    }

    /**
     * @dev 设置池子配置
     */
    function setPoolConfig(
        address token,
        uint256 distributionPeriod
    ) external onlyOwner onlyValidToken(token) {
        require(distributionPeriod > 0, Errors.InvalidParameter());

        PoolConfig storage pool = poolConfigs[token];
        pool.distributionPeriod = distributionPeriod;
    }

    /**
     * @dev 添加支持的代币
     */
    function addSupportedToken(address token) external onlyOwner {
        require(token != address(0), Errors.ZeroAddress());
        require(!isTokenSupported[token], TokenAlreadySupported());

        supportedTokens.push(token);
        isTokenSupported[token] = true;

        poolConfigs[token] = PoolConfig({
            token: token,
            totalCollected: 0,
            totalDistributed: 0,
            reserveAmount: 0,
            lastDistribution: 0,
            distributionPeriod: 86400,
            active: true
        });

        emit TokenSupported(token);
    }

    /**
     * @dev 移除支持的代币
     */
    function removeSupportedToken(address token) external onlyOwner {
        require(isTokenSupported[token], TokenNotSupported());

        isTokenSupported[token] = false;
        poolConfigs[token].active = false;

        // 从数组中移除
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[
                    supportedTokens.length - 1
                ];
                supportedTokens.pop();
                break;
            }
        }

        emit TokenUnsupported(token);
    }

    /**
     * @dev 启用紧急模式
     */
    function enableEmergencyMode() external onlyOwner {
        emergencyMode = true;

        // 设置紧急提取限额为余额的80%
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (isTokenSupported[supportedTokens[i]]) {
                uint256 balance = IERC20(supportedTokens[i]).balanceOf(
                    address(this)
                );
                emergencyWithdrawAmount[supportedTokens[i]] =
                    (balance * 80) /
                    100;
            }
        }

        emit EmergencyModeEnabled(block.timestamp);
    }

    /**
     * @dev 禁用紧急模式
     */
    function disableEmergencyMode() external onlyOwner {
        emergencyMode = false;

        // 清空紧急提取限额
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            emergencyWithdrawAmount[supportedTokens[i]] = 0;
        }

        emit EmergencyModeDisabled(block.timestamp);
    }

    /**
     * @dev 获取财库统计
     */
    function getTreasuryStatistics()
        external
        view
        returns (
            uint256 totalCollected,
            uint256 totalDistributed,
            uint256 reserveBalance,
            uint256 distributionCount_
        )
    {
        return (
            totalCollectedAllTokens,
            totalDistributedAllTokens,
            _getTotalReserveBalance(),
            distributionCount
        );
    }

    /**
     * @dev 获取代币统计
     */
    function getTokenStatistics(
        address token
    )
        external
        view
        onlyValidToken(token)
        returns (
            uint256 collected,
            uint256 distributed,
            uint256 reserve,
            uint256 pending,
            uint256 lastDistribution
        )
    {
        PoolConfig storage pool = poolConfigs[token];
        uint256 balance = IERC20(token).balanceOf(address(this));

        return (
            pool.totalCollected,
            pool.totalDistributed,
            pool.reserveAmount,
            balance > pool.reserveAmount ? balance - pool.reserveAmount : 0,
            pool.lastDistribution
        );
    }

    /**
     * @dev 获取支持的所有代币
     */
    function getSupportedTokens() external view returns (address[] memory) {
        address[] memory activeTokens = new address[](supportedTokens.length);
        uint256 count = 0;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (isTokenSupported[supportedTokens[i]]) {
                activeTokens[count] = supportedTokens[i];
                count++;
            }
        }

        // 调整数组大小
        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = activeTokens[i];
        }

        return result;
    }

    /**
     * @dev 分配收入 (内部函数)
     */
    function _distributeRevenue(address token) internal {
        PoolConfig storage pool = poolConfigs[token];
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 distributable = balance - pool.reserveAmount;

        if (distributable == 0) return;

        // 计算各部分金额
        uint256 platformAmount = (distributable *
            revenueSplit.platformReserve) / 10000;
        uint256 liquidityAmount = (distributable *
            revenueSplit.liquidityProviders) / 10000;
        uint256 aiAmount = (distributable * revenueSplit.aiProviders) / 10000;
        uint256 teamAmount = (distributable * revenueSplit.teamRewards) / 10000;
        uint256 treasuryAmount = (distributable * revenueSplit.treasury) /
            10000;

        // 执行分配
        if (platformAmount > 0) {
            IERC20(token).safeTransfer(platformReserveAddress, platformAmount);
            _recordDistribution(
                platformReserveAddress,
                platformAmount,
                "platform_reserve",
                token
            );
        }

        if (liquidityAmount > 0) {
            IERC20(token).safeTransfer(
                liquidityProviderAddress,
                liquidityAmount
            );
            _recordDistribution(
                liquidityProviderAddress,
                liquidityAmount,
                "liquidity_providers",
                token
            );
        }

        if (aiAmount > 0) {
            IERC20(token).safeTransfer(aiProviderAddress, aiAmount);
            _recordDistribution(
                aiProviderAddress,
                aiAmount,
                "ai_providers",
                token
            );
        }

        if (teamAmount > 0) {
            IERC20(token).safeTransfer(teamRewardAddress, teamAmount);
            _recordDistribution(
                teamRewardAddress,
                teamAmount,
                "team_rewards",
                token
            );
        }

        // 财库资金保留在合约中
        if (treasuryAmount > 0) {
            pool.reserveAmount += treasuryAmount;
            _recordDistribution(
                address(this),
                treasuryAmount,
                "treasury",
                token
            );
        }

        // 更新统计
        pool.totalDistributed += distributable;
        totalDistributedByToken[token] += distributable;
        totalDistributedAllTokens += distributable;
        pool.lastDistribution = block.timestamp;
        distributionCount++;

        // 标记收入记录为已分配
        for (uint256 i = 0; i < incomeHistory[token].length; i++) {
            if (!incomeHistory[token][i].distributed) {
                incomeHistory[token][i].distributed = true;
            }
        }

        emit Events.RevenueDistributed(
            platformAmount,
            treasuryAmount,
            aiAmount,
            block.timestamp
        );
    }

    /**
     * @dev 记录分配
     */
    function _recordDistribution(
        address recipient,
        uint256 amount,
        string memory category,
        address token
    ) internal {
        distributionHistory[token].push(
            DistributionRecord({
                amount: amount,
                timestamp: block.timestamp,
                recipient: recipient,
                category: category,
                token: token
            })
        );
    }

    /**
     * @dev 获取总储备余额
     */
    function _getTotalReserveBalance() internal view returns (uint256) {
        uint256 totalReserve = 0;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (isTokenSupported[supportedTokens[i]]) {
                totalReserve += poolConfigs[supportedTokens[i]].reserveAmount;
            }
        }

        return totalReserve;
    }

    // 事件定义
    event RevenueSplitUpdated(RevenueSplit newSplit);
    event TokenSupported(address indexed token);
    event TokenUnsupported(address indexed token);
    event DistributionFailed(address indexed token, string reason);
    event EmergencyModeEnabled(uint256 timestamp);
    event EmergencyModeDisabled(uint256 timestamp);
    event EmergencyWithdrawal(
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );

    // 错误定义
    error TokenNotSupported();
    error TokenAlreadySupported();
    error InvalidRevenueSplit();
    error EmergencyModeActive();
    error EmergencyModeNotActive();
    error EmptyArray();
    error InsufficientEmergencyAllowance();
}
