// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IPredictionFactory} from "./interfaces/IPredictionFactory.sol";
import {BinaryOptionMath} from "./libraries/BinaryOptionMath.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title RiskManager
 * @dev 风险管理合约
 */
contract RiskManager is ReentrancyGuard, Pausable, Ownable {
    // 风险参数
    struct RiskParameters {
        uint256 maxPoolSize; // 最大池子大小
        uint256 maxBetAmount; // 单次最大下注金额
        uint256 maxUserTotalExposure; // 用户最大总敞口
        uint256 maxPriceChange; // 最大价格变化 (基点)
        uint256 platformFee; // 平台手续费 (基点)
        uint256 minLiquidity; // 最小流动性要求
        uint256 maxPoolImbalance; // 最大池子不平衡比例 (基点)
        uint256 settlementDelay; // 结算延迟 (秒)
        uint256 maxEventsPerHour; // 每小时最大事件数
        uint256 circuitBreakerThreshold; // 熔断器阈值
    }

    // 用户风险限制
    struct UserRiskProfile {
        uint256 totalExposure; // 总敞口
        uint256 maxAllowedExposure; // 最大允许敞口
        uint256 bettingCount; // 下注次数
        uint256 lastBetTime; // 最后下注时间
        uint256 winningStreak; // 连胜次数
        uint256 losingStreak; // 连败次数
        bool restricted; // 是否受限
        uint256 restrictionUntil; // 限制到期时间
    }

    // 代币风险配置
    struct TokenRiskProfile {
        uint256 maxPoolSize; // 该代币最大池子大小
        uint256 maxPriceVolatility; // 最大价格波动性 (基点)
        uint256 minMarketCap; // 最小市值要求
        uint256 minVolume24h; // 最小24小时交易量
        uint256 confidenceThreshold; // 置信度阈值
        bool supported; // 是否支持
    }

    // 熔断器状态
    struct CircuitBreakerState {
        bool active; // 是否激活
        uint256 triggeredAt; // 触发时间
        string reason; // 触发原因
        uint256 cooldownUntil; // 冷却时间
    }

    // 状态变量
    RiskParameters public riskParams;
    mapping(address => UserRiskProfile) public userRiskProfiles;
    mapping(address => TokenRiskProfile) public tokenRiskProfiles;
    mapping(uint256 => uint256) public hourlyEventCount;
    mapping(uint256 => mapping(address => bool)) public hourlyEvents;

    CircuitBreakerState public circuitBreaker;

    // 合约地址
    address public predictionFactory;
    address public priceOracle;

    // 统计数据
    uint256 public totalManagedValue;
    uint256 public totalRiskExposure;
    uint256 public circuitBreakerTriggers;
    uint256 public restrictedUsers;

    // Internal check functions
    function _checkWhenNotRestricted() private {
        if (userRiskProfiles[msg.sender].restricted) {
            if (
                block.timestamp < userRiskProfiles[msg.sender].restrictionUntil
            ) {
                revert UserIsRestricted();
            } else {
                // 自动解除限制
                userRiskProfiles[msg.sender].restricted = false;
                restrictedUsers--;
            }
        }
    }

    function _checkWhenCircuitBreakerInactive() private {
        if (circuitBreaker.active) {
            if (block.timestamp < circuitBreaker.cooldownUntil) {
                revert CircuitBreakerActive();
            } else {
                // 自动重置熔断器
                _resetCircuitBreaker();
            }
        }
    }

    function _checkValidToken(address token) private view {
        if (!tokenRiskProfiles[token].supported) revert TokenNotSupported();
    }

    // Modifiers
    modifier onlyWhenNotRestricted() {
        _checkWhenNotRestricted();
        _;
    }

    modifier onlyWhenCircuitBreakerInactive() {
        _checkWhenCircuitBreakerInactive();
        _;
    }

    modifier onlyValidToken(address token) {
        _checkValidToken(token);
        _;
    }

    constructor(
        address _predictionFactory,
        address _priceOracle
    ) Ownable(msg.sender) {
        require(_predictionFactory != address(0), Errors.ZeroAddress());
        require(_priceOracle != address(0), Errors.ZeroAddress());

        predictionFactory = _predictionFactory;
        priceOracle = _priceOracle;

        // 初始化风险参数
        riskParams = RiskParameters({
            maxPoolSize: 1000000e18, // 1M ETH/USDT
            maxBetAmount: 10000e18, // 10K ETH/USDT
            maxUserTotalExposure: 50000e18, // 50K ETH/USDT
            maxPriceChange: 2000, // 20%
            platformFee: 300, // 3%
            minLiquidity: 100e18, // 100 ETH/USDT
            maxPoolImbalance: 8000, // 80%
            settlementDelay: 300, // 5分钟
            maxEventsPerHour: 100, // 100 events/hour
            circuitBreakerThreshold: 500000e18 // 500K ETH/USDT
        });
    }

    /**
     * @dev 验证事件参数
     */
    function validateEventParameters(
        IPredictionFactory.EventParams calldata params
    ) external view returns (bool isValid, string memory reason) {
        // 检查基础参数
        if (params.duration < 5 minutes || params.duration > 24 hours) {
            return (false, "Invalid duration");
        }

        if (params.strikePrice == 0 || params.targetPrice == 0) {
            return (false, "Invalid price");
        }

        // 检查价格变化
        if (
            !BinaryOptionMath.validatePriceChange(
                params.strikePrice,
                params.targetPrice,
                riskParams.maxPriceChange
            )
        ) {
            return (false, "Price change too high");
        }

        // 检查代币风险配置
        if (!tokenRiskProfiles[params.priceFeed].supported) {
            return (false, "Token not supported");
        }

        // 检查每小时事件限制
        if (hourlyEventCount[getCurrentHour()] >= riskParams.maxEventsPerHour) {
            return (false, "Hourly event limit exceeded");
        }

        // 检查熔断器
        if (circuitBreaker.active) {
            return (false, "Circuit breaker active");
        }

        return (true, "");
    }

    /**
     * @dev 验证用户下注
     */
    function validateUserBet(
        address user,
        uint256 betAmount,
        uint256 currentPoolSize,
        address token
    )
        external
        onlyWhenNotRestricted
        onlyWhenCircuitBreakerInactive
        onlyValidToken(token)
        returns (bool isValid, string memory reason)
    {
        UserRiskProfile storage userProfile = userRiskProfiles[user];

        // 检查下注金额限制
        if (betAmount > riskParams.maxBetAmount) {
            return (false, "Bet amount exceeds maximum");
        }

        // 检查用户总敞口
        if (
            userProfile.totalExposure + betAmount >
            userProfile.maxAllowedExposure
        ) {
            return (false, "User exposure limit exceeded");
        }

        // 检查池子大小限制
        TokenRiskProfile storage tokenProfile = tokenRiskProfiles[token];
        if (currentPoolSize + betAmount > tokenProfile.maxPoolSize) {
            return (false, "Pool size limit exceeded");
        }

        // 检查最小下注金额
        if (betAmount < 1e15) {
            // 0.001 ETH/USDT
            return (false, "Bet amount too small");
        }

        // 检查用户行为模式
        if (block.timestamp - userProfile.lastBetTime < 30 seconds) {
            return (false, "Too frequent betting");
        }

        return (true, "");
    }

    /**
     * @dev 验证池子平衡性
     */
    function validatePoolBalance(
        uint256 yesPool,
        uint256 noPool
    ) external view returns (bool isBalanced) {
        if (yesPool == 0 || noPool == 0) return false;

        uint256 totalPool = yesPool + noPool;
        uint256 maxPool = yesPool > noPool ? yesPool : noPool;
        uint256 imbalanceRatio = (maxPool * 10000) / totalPool;

        return imbalanceRatio <= (10000 + riskParams.maxPoolImbalance);
    }

    /**
     * @dev 更新用户风险状态
     */
    function updateUserRiskProfile(
        address user,
        uint256 betAmount,
        bool won
    ) external {
        require(msg.sender == predictionFactory, Unauthorized());

        UserRiskProfile storage profile = userRiskProfiles[user];

        // 更新敞口
        if (!won) {
            profile.totalExposure = profile.totalExposure > betAmount
                ? profile.totalExposure - betAmount
                : 0;
        }

        // 更新下注统计
        profile.bettingCount++;
        profile.lastBetTime = block.timestamp;

        // 更新胜负记录
        if (won) {
            profile.losingStreak = 0;
            profile.winningStreak++;

            // 连胜保护
            if (profile.winningStreak >= 5) {
                _restrictUser(user, 300); // 限制5分钟
            }
        } else {
            profile.winningStreak = 0;
            profile.losingStreak++;

            // 连败保护
            if (profile.losingStreak >= 10) {
                _restrictUser(user, 600); // 限制10分钟
            }
        }

        // 更新最大允许敞口
        _updateUserMaxExposure(user);

        // 检查是否需要触发熔断器
        _checkCircuitBreaker();
    }

    /**
     * @dev 设置代币风险配置
     */
    function setTokenRiskProfile(
        address token,
        TokenRiskProfile calldata profile
    ) external onlyOwner {
        require(token != address(0), Errors.ZeroAddress());
        tokenRiskProfiles[token] = profile;

        if (profile.supported) {
            emit TokenRiskProfileUpdated(token, profile);
        }
    }

    /**
     * @dev 更新风险参数
     */
    function updateRiskParameters(
        RiskParameters calldata newParams
    ) external onlyOwner {
        require(newParams.maxPoolSize > 0, Errors.InvalidParameter());
        require(newParams.maxBetAmount > 0, Errors.InvalidParameter());
        require(newParams.platformFee <= 1000, Errors.InvalidParameter()); // 最大0%

        riskParams = newParams;
        emit Events.RiskParametersUpdated(
            newParams.maxPoolSize,
            newParams.maxBetAmount,
            newParams.maxPriceChange,
            newParams.platformFee,
            block.timestamp
        );
    }

    /**
     * @dev 手动触发熔断器
     */
    function triggerCircuitBreaker(string calldata reason) external onlyOwner {
        if (circuitBreaker.active) return;

        circuitBreaker.active = true;
        circuitBreaker.triggeredAt = block.timestamp;
        circuitBreaker.reason = reason;
        circuitBreaker.cooldownUntil = block.timestamp + 3600; // 1小时冷却

        circuitBreakerTriggers++;

        emit Events.CircuitBreakerTriggered(reason, block.timestamp);
    }

    /**
     * @dev 重置熔断器
     */
    function resetCircuitBreaker() external onlyOwner {
        _resetCircuitBreaker();
    }

    /**
     * @dev 限制用户
     */
    function restrictUser(address user, uint256 duration) external onlyOwner {
        _restrictUser(user, duration);
    }

    /**
     * @dev 解除用户限制
     */
    function unrestrictUser(address user) external onlyOwner {
        if (userRiskProfiles[user].restricted) {
            userRiskProfiles[user].restricted = false;
            userRiskProfiles[user].restrictionUntil = 0;
            restrictedUsers--;
        }
    }

    /**
     * @dev 设置用户最大敞口
     */
    function setUserMaxExposure(
        address user,
        uint256 maxExposure
    ) external onlyOwner {
        userRiskProfiles[user].maxAllowedExposure = maxExposure;
    }

    /**
     * @dev 获取用户风险统计
     */
    function getUserRiskStatistics(
        address user
    )
        external
        view
        returns (
            uint256 totalExposure,
            uint256 maxAllowedExposure,
            uint256 bettingCount,
            uint256 winningStreak,
            uint256 losingStreak,
            bool restricted,
            uint256 restrictionTimeLeft
        )
    {
        UserRiskProfile storage profile = userRiskProfiles[user];

        return (
            profile.totalExposure,
            profile.maxAllowedExposure,
            profile.bettingCount,
            profile.winningStreak,
            profile.losingStreak,
            profile.restricted,
            profile.restrictionUntil > block.timestamp
                ? profile.restrictionUntil - block.timestamp
                : 0
        );
    }

    /**
     * @dev 获取系统风险统计
     */
    function getSystemRiskStatistics()
        external
        view
        returns (
            uint256 totalManagedValue_,
            uint256 totalRiskExposure_,
            uint256 circuitBreakerTriggers_,
            uint256 restrictedUsers_,
            bool circuitBreakerActive,
            uint256 hourlyEventCount_
        )
    {
        return (
            totalManagedValue,
            totalRiskExposure,
            circuitBreakerTriggers,
            restrictedUsers,
            circuitBreaker.active,
            hourlyEventCount[getCurrentHour()]
        );
    }

    /**
     * @dev 检查用户是否受限
     */
    function isUserRestricted(address user) external view returns (bool) {
        return
            userRiskProfiles[user].restricted &&
            block.timestamp < userRiskProfiles[user].restrictionUntil;
    }

    /**
     * @dev 获取当前小时
     */
    function getCurrentHour() internal view returns (uint256) {
        return block.timestamp / 3600;
    }

    /**
     * @dev 限制用户
     */
    function _restrictUser(address user, uint256 duration) internal {
        if (!userRiskProfiles[user].restricted) {
            restrictedUsers++;
        }

        userRiskProfiles[user].restricted = true;
        userRiskProfiles[user].restrictionUntil = block.timestamp + duration;

        emit UserRestricted(user, duration);
    }

    /**
     * @dev 更新用户最大敞口
     */
    function _updateUserMaxExposure(address user) internal {
        UserRiskProfile storage profile = userRiskProfiles[user];

        // 基于用户历史表现调整最大敞口
        uint256 baseExposure = riskParams.maxUserTotalExposure;

        if (profile.bettingCount >= 50) {
            // 老用户可以更高敞口
            profile.maxAllowedExposure = baseExposure * 2;
        } else if (profile.bettingCount >= 10) {
            // 中等用户
            profile.maxAllowedExposure = (baseExposure * 15) / 10;
        } else {
            // 新用户基础敞口
            profile.maxAllowedExposure = baseExposure;
        }

        // 根据胜负记录调整
        if (profile.winningStreak > 3) {
            profile.maxAllowedExposure = (profile.maxAllowedExposure * 8) / 10; // 降低20%
        }
    }

    /**
     * @dev 检查熔断器
     */
    function _checkCircuitBreaker() internal {
        if (totalRiskExposure > riskParams.circuitBreakerThreshold) {
            if (!circuitBreaker.active) {
                circuitBreaker.active = true;
                circuitBreaker.triggeredAt = block.timestamp;
                circuitBreaker.reason = "Risk exposure too high";
                circuitBreaker.cooldownUntil = block.timestamp + 3600;
                circuitBreakerTriggers++;
                emit Events.CircuitBreakerTriggered(
                    "Risk exposure too high",
                    block.timestamp
                );
            }
        }
    }

    /**
     * @dev 重置熔断器
     */
    function _resetCircuitBreaker() internal {
        if (circuitBreaker.active) {
            circuitBreaker.active = false;
            circuitBreaker.triggeredAt = 0;
            circuitBreaker.reason = "";
            circuitBreaker.cooldownUntil = 0;

            emit Events.CircuitBreakerReset(block.timestamp);
        }
    }

    // 事件定义
    event TokenRiskProfileUpdated(
        address indexed token,
        TokenRiskProfile profile
    );

    event UserRestricted(address indexed user, uint256 duration);

    event UserUnrestricted(address indexed user);

    // 错误定义
    error UserIsRestricted();
    error CircuitBreakerActive();
    error TokenNotSupported();
    error Unauthorized();
}
