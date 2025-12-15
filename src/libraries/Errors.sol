// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Errors {
    // 通用错误
    error ZeroAddress();
    error ZeroAmount();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidParameter();
    error InsufficientBalance();
    error InsufficientAllowance();
    error TransferFailed();

    // 事件相关错误
    error EventNotExists();
    error EventAlreadyExists();
    error EventNotActive();
    error EventNotSettled();
    error EventAlreadySettled();
    error EventNotLocked();
    error EventAlreadyCancelled();
    error BettingNotActive();
    error BettingEnded();
    error BettingNotStarted();
    error EventCreationDisabled();

    // 下注相关错误
    error BetAmountTooLow();
    error BetAmountTooHigh();
    error InvalidPosition();
    error BetAlreadyExists();
    error BetNotFound();
    error WinningsAlreadyClaimed();
    error NoWinningsToClaim();

    // 时间相关错误
    error EventNotEnded();
    error EventAlreadyEnded();
    error InvalidDuration();
    error InvalidTimestamp();

    // 价格相关错误
    error PriceFeedNotFound();
    error PriceNotAvailable();
    error PriceTooStale();
    error PriceInvalid();
    error InvalidPriceFeed();
    error PriceDeviationTooHigh();
    error InsufficientPriceData();
    error PriceUpdateFailed(address token);

    // AI预测相关错误
    error PredictionNotPaid();
    error PredictionAlreadyRequested();
    error PredictionNotFound();
    error PredictionNotCompleted();
    error InvalidQuestion();
    error AINotAvailable();

    // 支付相关错误
    error InsufficientPayment();
    error PaymentFailed();
    error InvalidPaymentAmount();
    error PaymentRefunded();

    // 权限相关错误
    error Unauthorized();
    error InsufficientRole();
    error RoleAlreadyGranted();
    error RoleNotGranted();

    // 风控相关错误
    error RiskLimitExceeded();
    error PoolSizeExceeded();
    error MaxBetAmountExceeded();
    error UserLimitExceeded();
    error PriceChangeTooHigh();
    error InvalidRiskParameters();

    // 熔断器相关错误
    error CircuitBreakerActive();
    error SystemPaused();
    error SystemNotPaused();

    // 财库相关错误
    error InsufficientFunds();
    error WithdrawFailed();
    error InvalidRecipient();
    error TreasuryEmpty();

    // 升级相关错误
    error UpgradeFailed();
    error InvalidImplementation();
    error UpgradeNotAllowed();

    // 批量操作相关错误
    error ArrayLengthMismatch();
    error BatchSizeExceeded();
    error BatchOperationFailed();

    // 字符串相关错误
    error EmptyString();
    error StringTooLong();
    error EmptyArray();

    // 枚举相关错误
    error InvalidEnumValue();

    // 数学运算相关错误
    error MathOverflow();
    error MathUnderflow();
    error DivisionByZero();

    // 常量定义
    uint256 public constant MAX_STRING_LENGTH = 256;
    uint256 public constant MAX_BATCH_SIZE = 50;
    uint256 public constant MIN_BET_AMOUNT = 1e15; // 0.001 ETH/USDT
    uint256 public constant MAX_DURATION = 24 hours;
    uint256 public constant MIN_DURATION = 5 minutes;
}