// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MemePredictionMarket
/// @dev 最简预测市场合约 - 单合约搞定所有功能
/// 流程: 后端创建事件 -> 用户下注 -> 任意时间平仓/1小时后结算 -> 领取奖励
contract MemePredictionMarket is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ 常量 ============
    uint256 public constant PRECISION = 1e18;
    uint256 public constant FEE_RATE = 300; // 3% 平台手续费 (基点)

    // ============ 事件 ============
    event EventCreated(uint256 indexed eventId, string tokenSymbol, uint256 basePrice, uint256 endTime);
    event BetPlaced(uint256 indexed eventId, address indexed user, bool isYes, uint256 amount, uint256 shares);
    event EarlySettled(uint256 indexed eventId, address indexed user, uint256 amount, uint256 pnl);
    event EventResolved(uint256 indexed eventId, uint256 finalPrice, bool yesWins);
    event RewardsClaimed(uint256 indexed eventId, address indexed user, uint256 amount);

    // ============ 错误 ============
    error InvalidAmount();
    error EventNotActive();
    error EventAlreadyResolved();
    error BettingEnded();
    error NoLiquidity();
    error NoRewards();
    error TransferFailed();
    error UnsupportedToken();

    // ============ 枚举 ============
    enum EventStatus {
        ACTIVE,
        RESOLVED,
        CANCELLED
    }

    // ============ 数据结构 ============
    struct Event {
        string tokenSymbol;       // 代币符号 (如 "PEPE")
        uint256 basePrice;        // 基准价格 (创建时)
        uint256 finalPrice;       // 结算价格 (可选)
        uint256 endTime;          // 结算时间
        uint256 yesPool;          // YES 池子
        uint256 noPool;           // NO 池子
        uint256 totalPool;        // 总池子 (yesPool + noPool)
        uint256 totalFees;        // 手续费
        bool yesWins;             // YES 是否获胜
        EventStatus status;       // 事件状态
        bool initialized;         // 是否已初始化
    }

    struct UserBet {
        uint256 eventId;
        bool isYes;
        uint256 amount;           // 下注金额
        uint256 shares;           // 获得的份额
        bool claimed;             // 是否已领取
    }

    // ============ 状态变量 ============
    uint256 private _nextEventId;
    mapping(uint256 => Event) public events;
    mapping(uint256 => mapping(address => UserBet)) public userBets;
    mapping(uint256 => address[]) public eventUsers;
    mapping(address => bool) public supportedTokens;
    mapping(uint256 => mapping(address => bool)) public hasParticipated;

    address public feeRecipient;
    address public owner;

    // ============ 修饰符 ============
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ============ 构造函数 ============
    constructor(address _feeRecipient, address[] memory _supportedTokens) {
        owner = msg.sender;
        feeRecipient = _feeRecipient;
        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            supportedTokens[_supportedTokens[i]] = true;
        }
        _nextEventId = 1;
    }

    // ============ 核心功能: 后端创建事件 ============
    function createEvent(
        string calldata tokenSymbol,
        uint256 basePrice,
        uint256 durationSeconds
    ) external onlyOwner returns (uint256 eventId) {
        require(bytes(tokenSymbol).length > 0, "Empty symbol");
        require(basePrice > 0, "Invalid price");
        require(durationSeconds >= 300 && durationSeconds <= 86400, "Invalid duration");

        eventId = _nextEventId++;
        uint256 endTime = block.timestamp + durationSeconds;

        events[eventId] = Event({
            tokenSymbol: tokenSymbol,
            basePrice: basePrice,
            finalPrice: 0,
            endTime: endTime,
            yesPool: 0,
            noPool: 0,
            totalPool: 0,
            totalFees: 0,
            yesWins: false,
            status: EventStatus.ACTIVE,
            initialized: true
        });

        emit EventCreated(eventId, tokenSymbol, basePrice, endTime);
        return eventId;
    }

    // ============ 核心功能: 用户下注 ============
    function placeBet(
        uint256 eventId,
        bool isYes,
        uint256 amount,
        address token
    ) external payable nonReentrant {
        require(supportedTokens[token], "Unsupported token");
        require(msg.value == 0, "No ETH expected");

        Event storage evt = _getEvent(eventId);
        require(evt.status == EventStatus.ACTIVE, "Event not active");
        require(block.timestamp < evt.endTime, "Betting ended");

        // 接收 ERC20
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares = _calculateShares(amount, evt.yesPool, evt.noPool, isYes);

        if (isYes) {
            evt.yesPool += amount;
        } else {
            evt.noPool += amount;
        }
        evt.totalPool += amount;

        if (!hasParticipated[eventId][msg.sender]) {
            hasParticipated[eventId][msg.sender] = true;
            eventUsers[eventId].push(msg.sender);
        }

        userBets[eventId][msg.sender] = UserBet({
            eventId: eventId,
            isYes: isYes,
            amount: amount,
            shares: shares,
            claimed: false
        });

        emit BetPlaced(eventId, msg.sender, isYes, amount, shares);
    }

    // ============ 核心功能: 结算事件 ============
    function resolveEvent(uint256 eventId, uint256 finalPrice) external onlyOwner {
        Event storage evt = _getEvent(eventId);
        require(evt.status == EventStatus.ACTIVE, "Event not active");
        require(block.timestamp >= evt.endTime, "Not ended yet");

        bool yesWins = finalPrice >= evt.basePrice;

        evt.finalPrice = finalPrice;
        evt.yesWins = yesWins;
        evt.status = EventStatus.RESOLVED;

        emit EventResolved(eventId, finalPrice, yesWins);
    }

    // ============ 核心功能: 批量结算 ============
    function batchResolve(uint256[] calldata eventIds, uint256[] calldata finalPrices) external onlyOwner {
        require(eventIds.length == finalPrices.length, "Length mismatch");
        for (uint256 i = 0; i < eventIds.length; i++) {
            _resolveEventInternal(eventIds[i], finalPrices[i]);
        }
    }

    // ============ 核心功能: 提前平仓 ============
    function earlySettle(uint256 eventId) external nonReentrant {
        Event storage evt = _getEvent(eventId);
        require(evt.status == EventStatus.ACTIVE, "Event not active");
        require(block.timestamp < evt.endTime, "Betting ended");

        UserBet storage bet = userBets[eventId][msg.sender];
        require(bet.amount > 0 && !bet.claimed, "No bet or already settled");

        uint256 payout;
        if (bet.isYes) {
            uint256 noShare = evt.noPool > 0 ? (bet.shares * evt.noPool) / evt.yesPool : 0;
            payout = bet.amount + noShare;
        } else {
            uint256 yesShare = evt.yesPool > 0 ? (bet.shares * evt.yesPool) / evt.noPool : 0;
            payout = bet.amount + yesShare;
        }

        uint256 fee = (payout - bet.amount) * FEE_RATE / 10000;
        evt.totalFees += fee;
        payout -= fee;

        bet.claimed = true;
        _safeTransfer(payable(msg.sender), payout);

        emit EarlySettled(eventId, msg.sender, bet.amount, payout - bet.amount);
    }

    // ============ 核心功能: 领取奖励 ============
    function claimRewards(uint256 eventId) external nonReentrant {
        Event storage evt = _getEvent(eventId);
        require(evt.status == EventStatus.RESOLVED, "Not resolved");

        UserBet storage bet = userBets[eventId][msg.sender];
        require(bet.amount > 0, "No bet");
        require(!bet.claimed, "Already claimed");
        require(_isWinner(evt, bet), "You lost");

        uint256 winningPool = evt.yesWins ? evt.yesPool : evt.noPool;
        uint256 losingPool = evt.yesWins ? evt.noPool : evt.yesPool;
        uint256 payout = _calculatePayout(bet.amount, bet.shares, winningPool, losingPool);

        uint256 fee = (payout - bet.amount) * FEE_RATE / 10000;
        evt.totalFees += fee;
        payout -= fee;

        bet.claimed = true;
        _safeTransfer(payable(msg.sender), payout);

        emit RewardsClaimed(eventId, msg.sender, payout);
    }

    // ============ 管理员函数 ============
    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "Zero address");
        feeRecipient = recipient;
    }

    function addSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = true;
    }

    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
    }

    function rescueETH(uint256 amount) external onlyOwner {
        _safeTransfer(payable(msg.sender), amount);
    }

    function rescueToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    // ============ 查询函数 ============
    function getEvent(uint256 eventId) external view returns (Event memory) {
        return events[eventId];
    }

    function getUserBet(uint256 eventId, address user) external view returns (UserBet memory) {
        return userBets[eventId][user];
    }

    function getCurrentOdds(uint256 eventId) external view returns (uint256 yesOdds, uint256 noOdds) {
        Event storage evt = events[eventId];
        require(evt.initialized, "Event not found");
        require(evt.status == EventStatus.ACTIVE, "Event not active");

        uint256 totalPool = evt.yesPool + evt.noPool;
        if (totalPool == 0) {
            return (PRECISION / 2, PRECISION / 2);
        }
        yesOdds = (evt.yesPool * PRECISION) / totalPool;
        noOdds = (evt.noPool * PRECISION) / totalPool;
    }

    function getPotentialPayout(uint256 eventId, address user) external view returns (uint256 payout) {
        Event storage evt = events[eventId];
        UserBet storage bet = userBets[eventId][user];

        if (bet.amount == 0) return 0;

        if (evt.status == EventStatus.ACTIVE) {
            if (bet.isYes) {
                uint256 noShare = evt.noPool > 0 ? (bet.shares * evt.noPool) / evt.yesPool : 0;
                payout = bet.amount + noShare;
            } else {
                uint256 yesShare = evt.yesPool > 0 ? (bet.shares * evt.yesPool) / evt.noPool : 0;
                payout = bet.amount + yesShare;
            }
        } else if (evt.status == EventStatus.RESOLVED) {
            if (_isWinner(evt, bet)) {
                uint256 winningPool = evt.yesWins ? evt.yesPool : evt.noPool;
                uint256 losingPool = evt.yesWins ? evt.noPool : evt.yesPool;
                payout = _calculatePayout(bet.amount, bet.shares, winningPool, losingPool);
            }
        }
    }

    // ============ 内部函数 ============
    function _resolveEventInternal(uint256 eventId, uint256 finalPrice) internal {
        Event storage evt = _getEvent(eventId);
        require(evt.status == EventStatus.ACTIVE, "Event not active");
        require(block.timestamp >= evt.endTime, "Not ended yet");

        bool yesWins = finalPrice >= evt.basePrice;
        evt.finalPrice = finalPrice;
        evt.yesWins = yesWins;
        evt.status = EventStatus.RESOLVED;

        emit EventResolved(eventId, finalPrice, yesWins);
    }

    function _getEvent(uint256 eventId) internal view returns (Event storage) {
        Event storage evt = events[eventId];
        require(evt.initialized, "Event not found");
        return evt;
    }

    function _calculateShares(
        uint256 amount,
        uint256 yesPool,
        uint256 noPool,
        bool isYes
    ) internal pure returns (uint256) {
        uint256 currentPool = isYes ? yesPool : noPool;
        uint256 totalPool = yesPool + noPool;

        if (currentPool == 0) {
            return amount;
        }

        uint256 newPool = currentPool + amount;
        return (amount * totalPool) / newPool;
    }

    function _calculatePayout(
        uint256 amount,
        uint256 shares,
        uint256 winningPool,
        uint256 losingPool
    ) internal pure returns (uint256) {
        uint256 payout = amount;

        if (winningPool > 0 && shares > 0) {
            uint256 profit = (shares * losingPool) / winningPool;
            payout += profit;
        }

        return payout;
    }

    function _isWinner(Event storage evt, UserBet storage bet) internal view returns (bool) {
        if (evt.yesWins && bet.isYes) return true;
        if (!evt.yesWins && !bet.isYes) return true;
        return false;
    }

    function _safeTransfer(address payable to, uint256 amount) internal {
        require(to.send(amount), "Transfer failed");
    }

    receive() external payable {}
}
