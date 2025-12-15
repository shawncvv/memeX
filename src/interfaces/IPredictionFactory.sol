// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPredictionFactory {
    struct EventParams {
        string tokenSymbol;
        address priceFeed;
        uint256 duration; // 持续时间 (秒)
        uint256 strikePrice; // 基准价格
        uint256 targetPrice; // 目标价格
        uint256 tolerance; // 价格容差
    }

    event EventCreated(
        address indexed eventAddress,
        string indexed tokenSymbol,
        uint256 duration,
        uint256 targetPrice
    );

    event EventCreationToggled(bool enabled);

    function createEvent(
        EventParams calldata params
    ) external returns (address);

    function getActiveEvents() external view returns (address[] memory);

    function getEventsByToken(
        string calldata tokenSymbol
    ) external view returns (address[] memory);

    function toggleEventCreation() external;

    function updateEventTemplate(address newTemplate) external;

    function checkEventActive(
        address eventAddress
    ) external view returns (bool);
}
