// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPriceOracle {
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 decimals;
        bool isValid;
    }

    struct PriceFeed {
        address feedAddress;
        uint256 heartbeat;    // 最大心跳时间
        uint256 deviationThreshold; // 价格偏差阈值
        bool active;
    }

    event PriceFeedAdded(address indexed token, address indexed feed);
    event PriceFeedUpdated(address indexed token, address indexed feed);
    event PriceFeedRemoved(address indexed token);
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);

    function getPrice(address token) external view returns (uint256 price, uint256 timestamp);
    function getPriceWithValidation(address token) external view returns (uint256 price);
    function validatePrice(address token, uint256 price) external view returns (bool);
    function addPriceFeed(address token, address feed, uint256 heartbeat, uint256 deviationThreshold) external;
    function updatePriceFeed(address token, address feed) external;
    function removePriceFeed(address token) external;
    function isTokenSupported(address token) external view returns (bool);
    function getPriceFeed(address token) external view returns (PriceFeed memory);
}