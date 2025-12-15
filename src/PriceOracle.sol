// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title PriceOracle
 * @dev 价格预言机合约
 */
contract PriceOracle is IPriceOracle, ReentrancyGuard, Pausable, Ownable {
    constructor() Ownable(msg.sender) {}

    // 价格feed配置
    mapping(address => PriceFeed) public priceFeeds;
    address[] public supportedTokens;

    // TWAP相关
    uint256 public constant TWAP_WINDOW = 300; // 5分钟
    uint256 public constant MAX_PRICE_POINTS = 10;

    // 价格历史记录 (用于TWAP计算)
    struct PricePoint {
        uint256 price;
        uint256 timestamp;
    }

    mapping(address => PricePoint[]) public priceHistory;

    // 配置
    uint256 public defaultHeartbeat = 300; // 5分钟
    uint256 public defaultDeviationThreshold = 1000; // 10%

    // Internal check functions
    function _checkSupportedToken(address token) private view {
        if (!priceFeeds[token].active) revert Errors.PriceFeedNotFound();
    }

    function _checkValidFeed(address feed) private pure {
        if (feed == address(0)) revert Errors.ZeroAddress();
    }

    // Modifiers
    modifier onlySupportedToken(address token) {
        _checkSupportedToken(token);
        _;
    }

    modifier onlyValidFeed(address feed) {
        _checkValidFeed(feed);
        _;
    }

    /**
     * @dev 添加价格feed
     */
    function addPriceFeed(
        address token,
        address feed,
        uint256 heartbeat,
        uint256 deviationThreshold
    ) external override onlyOwner onlyValidFeed(feed) {
        require(token != address(0), Errors.ZeroAddress());
        require(heartbeat > 0, Errors.InvalidParameter());
        require(deviationThreshold > 0, Errors.InvalidParameter());

        priceFeeds[token] = PriceFeed({
            feedAddress: feed,
            heartbeat: heartbeat,
            deviationThreshold: deviationThreshold,
            active: true
        });

        // 如果是新的代币，添加到支持列表
        if (!priceFeeds[token].active) {
            supportedTokens.push(token);
        }

        // 获取初始价格
        _updatePriceHistory(token);

        emit PriceFeedAdded(token, feed);
        emit Events.PriceFeedAdded(token, feed, heartbeat, deviationThreshold);
    }

    /**
     * @dev 更新价格feed
     */
    function updatePriceFeed(
        address token,
        address newFeed
    ) external override onlyOwner onlyValidFeed(newFeed) {
        if (!priceFeeds[token].active) revert Errors.PriceFeedNotFound();

        priceFeeds[token].feedAddress = newFeed;

        // 更新价格历史
        _updatePriceHistory(token);

        emit PriceFeedUpdated(token, newFeed);
    }

    /**
     * @dev 移除价格feed
     */
    function removePriceFeed(address token) external override onlyOwner {
        if (!priceFeeds[token].active) revert Errors.PriceFeedNotFound();

        priceFeeds[token].active = false;

        // 从支持列表中移除
        _removeFromSupportedTokens(token);

        emit PriceFeedRemoved(token);
    }

    /**
     * @dev 获取价格
     */
    function getPrice(
        address token
    )
        external
        view
        override
        onlySupportedToken(token)
        returns (uint256 price, uint256 timestamp)
    {
        PriceFeed memory feed = priceFeeds[token];

        try AggregatorV3Interface(feed.feedAddress).latestRoundData() returns (
            uint80 /* roundId */,
            int256 answer,
            uint256 /* startedAt */,
            uint256 updatedAt,
            uint80 /* answeredInRound */
        ) {
            if (answer <= 0) revert Errors.PriceInvalid();

            // 检查价格是否太旧
            if (block.timestamp - updatedAt > feed.heartbeat) {
                revert Errors.PriceTooStale();
            }

            // 转换为18位小数
            uint256 decimals = _getDecimals(feed.feedAddress);
            // 安全：已在上面检查 answer > 0
            // forge-lint: disable-next-line(unsafe-typecast)
            price = uint256(answer) * (10 ** (18 - decimals));
            timestamp = updatedAt;

            return (price, timestamp);
        } catch {
            revert Errors.PriceNotAvailable();
        }
    }

    /**
     * @dev 获取带验证的价格
     */
    function getPriceWithValidation(
        address token
    ) external view override onlySupportedToken(token) returns (uint256 price) {
        (uint256 currentPrice, ) = this.getPrice(token);

        // 验证价格偏差
        if (!_validatePriceDeviation(token, currentPrice)) {
            revert Errors.PriceDeviationTooHigh();
        }

        return currentPrice;
    }

    /**
     * @dev 验证价格
     */
    function validatePrice(
        address token,
        uint256 price
    ) external view override returns (bool) {
        if (!priceFeeds[token].active) return false;

        // 获取当前价格
        try this.getPrice(token) returns (
            uint256 currentPrice,
            uint256 /*timestamp*/
        ) {
            // 检查价格偏差
            uint256 deviation = currentPrice > price
                ? ((currentPrice - price) * 10000) / currentPrice
                : ((price - currentPrice) * 10000) / currentPrice;

            return deviation <= priceFeeds[token].deviationThreshold;
        } catch {
            return false;
        }
    }

    /**
     * @dev 检查代币是否支持
     */
    function isTokenSupported(
        address token
    ) external view override returns (bool) {
        return priceFeeds[token].active;
    }

    /**
     * @dev 获取价格feed配置
     */
    function getPriceFeed(
        address token
    ) external view override returns (PriceFeed memory) {
        return priceFeeds[token];
    }

    /**
     * @dev 获取TWAP价格
     */
    function getTwapPrice(
        address token,
        uint256 window
    ) external view onlySupportedToken(token) returns (uint256 twapPrice) {
        PricePoint[] memory history = priceHistory[token];

        if (history.length < 2) revert Errors.InsufficientPriceData();

        uint256 cutoffTime = block.timestamp - window;
        uint256 totalWeightedPrice = 0;
        uint256 totalWeight = 0;

        for (uint256 i = history.length - 1; i >= 0; i--) {
            if (history[i].timestamp < cutoffTime) break;

            uint256 weight = i == 0
                ? 1
                : history[i].timestamp - history[i - 1].timestamp;
            totalWeightedPrice += history[i].price * weight;
            totalWeight += weight;
        }

        require(totalWeight > 0, Errors.DivisionByZero());
        return totalWeightedPrice / totalWeight;
    }

    /**
     * @dev 更新价格历史
     */
    function updatePriceHistory(
        address token
    ) external nonReentrant onlySupportedToken(token) {
        _updatePriceHistory(token);
    }

    /**
     * @dev 批量更新价格历史
     */
    function batchUpdatePriceHistory(
        address[] calldata tokens
    ) external nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (priceFeeds[tokens[i]].active) {
                try this.updatePriceHistory(tokens[i]) {
                    // 成功更新
                } catch {
                    // 记录失败的更新 - 静默处理
                }
            }
        }
    }

    /**
     * @dev 获取价格历史
     */
    function getPriceHistory(
        address token,
        uint256 limit
    ) external view returns (PricePoint[] memory) {
        PricePoint[] memory history = priceHistory[token];
        uint256 length = limit > 0 && limit < history.length
            ? limit
            : history.length;

        PricePoint[] memory result = new PricePoint[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = history[history.length - length + i];
        }

        return result;
    }

    /**
     * @dev 获取支持的代币列表
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    /**
     * @dev 设置默认配置
     */
    function setDefaultConfig(
        uint256 newHeartbeat,
        uint256 newDeviationThreshold
    ) external onlyOwner {
        defaultHeartbeat = newHeartbeat;
        defaultDeviationThreshold = newDeviationThreshold;
    }

    /**
     * @dev 获取价格feed的小数位数
     */
    function _getDecimals(address feed) internal view returns (uint256) {
        try AggregatorV3Interface(feed).decimals() returns (uint8 decimals) {
            return uint256(decimals);
        } catch {
            return 18; // 默认18位小数
        }
    }

    /**
     * @dev 验证价格偏差
     */
    function _validatePriceDeviation(
        address token,
        uint256 currentPrice
    ) internal view returns (bool) {
        PricePoint[] memory history = priceHistory[token];

        if (history.length == 0) return true;

        uint256 lastPrice = history[history.length - 1].price;
        uint256 deviation = currentPrice > lastPrice
            ? ((currentPrice - lastPrice) * 10000) / lastPrice
            : ((lastPrice - currentPrice) * 10000) / lastPrice;

        return deviation <= priceFeeds[token].deviationThreshold;
    }

    /**
     * @dev 更新价格历史
     */
    function _updatePriceHistory(address token) internal {
        try this.getPrice(token) returns (uint256 price, uint256 timestamp) {
            PricePoint[] storage history = priceHistory[token];

            // 添加新的价格点
            history.push(PricePoint({price: price, timestamp: timestamp}));

            // 限制历史记录数量
            if (history.length > MAX_PRICE_POINTS) {
                // 移除最旧的记录
                for (uint256 i = 0; i < history.length - 1; i++) {
                    history[i] = history[i + 1];
                }
                history.pop();
            }

            emit PriceUpdated(token, price, timestamp);
            emit Events.PriceUpdated(token, price, timestamp);
        } catch {
            revert Errors.PriceUpdateFailed(token);
        }
    }

    /**
     * @dev 从支持的代币列表中移除
     */
    function _removeFromSupportedTokens(address token) internal {
        uint256 length = supportedTokens.length;

        for (uint256 i = 0; i < length; i++) {
            if (supportedTokens[i] == token) {
                // 移动最后一个元素到当前位置
                supportedTokens[i] = supportedTokens[length - 1];
                supportedTokens.pop();
                break;
            }
        }
    }

    /**
     * @dev 暂停合约
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 恢复合约
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 紧急移除代币
     */
    function emergencyRemoveToken(address token) external onlyOwner {
        if (priceFeeds[token].active) {
            priceFeeds[token].active = false;
            _removeFromSupportedTokens(token);
            emit PriceFeedRemoved(token);
        }
    }
}
