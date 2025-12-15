// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Events {
    // 事件相关事件
    event EventCreated(
        address indexed eventAddress,
        string indexed tokenSymbol,
        uint256 duration,
        uint256 targetPrice,
        uint256 timestamp
    );

    event BetPlaced(
        address indexed user,
        address indexed eventAddress,
        uint256 position,
        uint256 amount,
        uint256 timestamp
    );

    event EventSettled(
        address indexed eventAddress,
        uint256 winningPosition,
        uint256 finalPrice,
        uint256 totalPool,
        uint256 timestamp
    );

    event WinningsClaimed(
        address indexed user,
        address indexed eventAddress,
        uint256 amount,
        uint256 timestamp
    );

    event EventCancelled(
        address indexed eventAddress,
        string reason,
        uint256 timestamp
    );

    event EventLocked(
        address indexed eventAddress,
        uint256 timestamp
    );

    // 支付相关事件
    event PaymentForAI(
        address indexed user,
        bytes32 indexed requestId,
        uint256 amount,
        uint256 timestamp
    );

    event AI_predictionRequested(
        bytes32 indexed requestId,
        address indexed user,
        bytes32 indexed eventId,
        string question,
        uint256 timestamp
    );

    event AI_predictionCompleted(
        bytes32 indexed requestId,
        uint256 recommendation,
        uint256 confidence,
        string reasoning,
        uint256 timestamp
    );

    // 价格相关事件
    event PriceUpdated(
        address indexed token,
        uint256 price,
        uint256 timestamp
    );

    event PriceFeedAdded(
        address indexed token,
        address indexed feed,
        uint256 heartbeat,
        uint256 deviationThreshold
    );

    // 风控相关事件
    event RiskParametersUpdated(
        uint256 maxPoolSize,
        uint256 maxBetAmount,
        uint256 maxPriceChange,
        uint256 platformFee,
        uint256 timestamp
    );

    event CircuitBreakerTriggered(
        string reason,
        uint256 timestamp
    );

    event CircuitBreakerReset(
        uint256 timestamp
    );

    // 权限相关事件
    event RoleGranted(
        bytes32 indexed role,
        address indexed account,
        address indexed sender,
        uint256 timestamp
    );

    event RoleRevoked(
        bytes32 indexed role,
        address indexed account,
        address indexed sender,
        uint256 timestamp
    );

    // 财库相关事件
    event FeesCollected(
        uint256 amount,
        uint256 timestamp
    );

    event FundsWithdrawn(
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );

    event RevenueDistributed(
        uint256 platformAmount,
        uint256 treasuryAmount,
        uint256 aiProviderAmount,
        uint256 timestamp
    );
}