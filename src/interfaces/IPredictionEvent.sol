// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPredictionEvent {
    enum Position { YES, NO }
    enum Phase { OPEN, LOCKED, SETTLED, CANCELLED }

    struct EventParams {
        string tokenSymbol;
        address priceFeed;
        uint256 duration;
        uint256 strikePrice;
        uint256 targetPrice;
        uint256 tolerance;
        uint256 startTime;
        uint256 endTime;
    }

    struct Event {
        string tokenSymbol;
        address priceFeed;
        uint256 startTime;
        uint256 endTime;
        uint256 strikePrice;
        uint256 targetPrice;
        uint256 tolerance;
        Position winningPosition;
        Phase currentPhase;
        uint256 yesPool;
        uint256 noPool;
        uint256 totalPool;
        bool exists;
    }

    struct Bet {
        address user;
        Position position;
        uint256 amount;
        uint256 timestamp;
        bool claimed;
    }

    event BetPlaced(address indexed user, Position position, uint256 amount);
    event EventSettled(Position winningPosition, uint256 finalPrice);
    event WinningsClaimed(address indexed user, uint256 amount);
    event EventCancelled(string reason);
    event EventLocked();

    function initialize(EventParams memory params, address _priceOracle, address _aiOracle, address _treasury, address[] memory _supportedTokens) external;
    function placeBet(Position position, uint256 amount) external payable;
    function settle() external;
    function claimWinnings() external;
    function cancelEvent(string calldata reason) external;
    function getCurrentOdds() external view returns (uint256 yesOdds, uint256 noOdds);
    function getUserWinnings(address user) external view returns (uint256);
    function getUserBets(address user) external view returns (Bet[] memory);
    function getEventInfo() external view returns (Event memory);
}