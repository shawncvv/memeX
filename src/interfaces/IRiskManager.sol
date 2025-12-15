// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPredictionFactory} from "./IPredictionFactory.sol";

interface IRiskManager {
    /**
     * @dev 验证事件参数
     */
    function validateEventParameters(
        IPredictionFactory.EventParams calldata params
    ) external view returns (bool isValid, string memory reason);

    /**
     * @dev 验证用户下注
     */
    function validateUserBet(
        address user,
        uint256 betAmount,
        uint256 currentPoolSize,
        address token
    ) external view returns (bool isValid, string memory reason);

    /**
     * @dev 验证池子平衡性
     */
    function validatePoolBalance(uint256 yesPool, uint256 noPool) external view returns (bool isBalanced);

    /**
     * @dev 更新用户风险状态
     */
    function updateUserRiskProfile(
        address user,
        uint256 betAmount,
        bool won
    ) external;

    /**
     * @dev 获取用户风险统计
     */
    function getUserRiskStatistics(address user) external view returns (
        uint256 totalExposure,
        uint256 maxAllowedExposure,
        uint256 bettingCount,
        uint256 winningStreak,
        uint256 losingStreak,
        bool restricted,
        uint256 restrictionTimeLeft
    );

    /**
     * @dev 获取系统风险统计
     */
    function getSystemRiskStatistics() external view returns (
        uint256 totalManagedValue_,
        uint256 totalRiskExposure_,
        uint256 circuitBreakerTriggers_,
        uint256 restrictedUsers_,
        bool circuitBreakerActive,
        uint256 hourlyEventCount_
    );

    /**
     * @dev 检查用户是否受限
     */
    function isUserRestricted(address user) external view returns (bool);
}