// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

library BinaryOptionMath {
    uint256 private constant PRECISION = 10000; // 4 decimals for odds calculation

    /**
     * @dev 计算当前赔率
     * @param yesPool YES方资金池大小
     * @param noPool NO方资金池大小
     * @param platformFee 平台手续费 (基点)
     * @return yesOdds YES方赔率 (基点)
     * @return noOdds NO方赔率 (基点)
     */
    function calculateOdds(
        uint256 yesPool,
        uint256 noPool,
        uint256 platformFee
    ) internal pure returns (uint256 yesOdds, uint256 noOdds) {
        if (yesPool == 0 || noPool == 0) {
            return (PRECISION, PRECISION); // 默认1:1赔率
        }

        uint256 totalPool = yesPool + noPool;
        uint256 feeAmount = (totalPool * platformFee) / PRECISION;
        uint256 rewardPool = totalPool - feeAmount;

        // 赔率 = 奖励池 / 对方池
        yesOdds = (rewardPool * PRECISION) / yesPool;
        noOdds = (rewardPool * PRECISION) / noPool;

        // 确保最小赔率
        uint256 minOdds = PRECISION + 1000; // 最小1.1倍
        yesOdds = yesOdds < minOdds ? minOdds : yesOdds;
        noOdds = noOdds < minOdds ? minOdds : noOdds;
    }

    /**
     * @dev 计算用户获胜金额
     * @param betAmount 下注金额
     * @param odds 赔率 (基点)
     * @return winnings 获胜金额 (包括本金)
     */
    function calculateWinnings(
        uint256 betAmount,
        uint256 odds
    ) internal pure returns (uint256 winnings) {
        return (betAmount * odds) / PRECISION;
    }

    /**
     * @dev 计算平台手续费
     * @param totalPool 总资金池
     * @param platformFee 手续费率 (基点)
     * @return fee 手续费金额
     */
    function calculatePlatformFee(
        uint256 totalPool,
        uint256 platformFee
    ) internal pure returns (uint256 fee) {
        return (totalPool * platformFee) / PRECISION;
    }

    /**
     * @dev 验证价格变化是否在允许范围内
     * @param currentPrice 当前价格
     * @param targetPrice 目标价格
     * @param maxChangePercent 最大变化百分比 (基点)
     * @return isValid 是否有效
     */
    function validatePriceChange(
        uint256 currentPrice,
        uint256 targetPrice,
        uint256 maxChangePercent
    ) internal pure returns (bool isValid) {
        if (currentPrice == 0) return false;

        uint256 changePercent;
        if (targetPrice > currentPrice) {
            changePercent =
                ((targetPrice - currentPrice) * PRECISION) /
                currentPrice;
        } else {
            changePercent =
                ((currentPrice - targetPrice) * PRECISION) /
                currentPrice;
        }

        return changePercent <= maxChangePercent;
    }

    /**
     * @dev 检查价格是否在容差范围内
     * @param price1 价格1
     * @param price2 价格2
     * @param tolerance 容差 (基点)
     * @return isWithinTolerance 是否在容差内
     */
    function isWithinTolerance(
        uint256 price1,
        uint256 price2,
        uint256 tolerance
    ) internal pure returns (bool) {
        if (price1 == 0 || price2 == 0) return false;

        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;
        uint256 toleranceAmount = (price1 * tolerance) / PRECISION;

        return diff <= toleranceAmount;
    }

    /**
     * @dev 计算时间加权平均价格 (TWAP)
     * @param prices 价格数组
     * @param timestamps 时间戳数组
     * @param window 时间窗口 (秒)
     * @return twap TWAP价格
     */
    function calculateTwap(
        uint256[] memory prices,
        uint256[] memory timestamps,
        uint256 window
    ) internal pure returns (uint256 twap) {
        require(prices.length == timestamps.length, "Array length mismatch");
        require(prices.length > 0, "Empty arrays");

        uint256 totalWeightedPrice = 0;
        uint256 totalWeight = 0;
        uint256 startTime = timestamps[0];

        for (uint256 i = 0; i < prices.length; i++) {
            if (timestamps[i] - startTime > window) break;

            uint256 weight = i == 0 ? 1 : timestamps[i] - timestamps[i - 1];
            totalWeightedPrice += prices[i] * weight;
            totalWeight += weight;
        }

        require(totalWeight > 0, "No valid data in window");
        return totalWeightedPrice / totalWeight;
    }

    /**
     * @dev 安全除法，避免除零错误
     * @param a 被除数
     * @param b 除数
     * @param defaultValue 除零时返回的默认值
     * @return result 除法结果
     */
    function safeDiv(
        uint256 a,
        uint256 b,
        uint256 defaultValue
    ) internal pure returns (uint256 result) {
        return b == 0 ? defaultValue : a / b;
    }

    /**
     * @dev 将基点转换为百分比字符串
     * @param basisPoints 基点
     * @return percentage 百分比字符串
     */
    function basisPointsToPercentage(
        uint256 basisPoints
    ) internal pure returns (string memory percentage) {
        uint256 whole = basisPoints / 100;
        uint256 decimal = basisPoints % 100;

        if (decimal == 0) {
            return Strings.toString(whole);
        } else {
            return
                string(
                    abi.encodePacked(
                        Strings.toString(whole),
                        ".",
                        decimal < 10 ? "0" : "",
                        Strings.toString(decimal)
                    )
                );
        }
    }
}
