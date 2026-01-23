// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MemePredictionMarket
/// @dev 简化预测市场合约 - 仅支持 USDC
contract MemePredictionMarket is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ 常量 ============
    uint256 public constant PRECISION = 1e18;
    uint256 public constant FEE_RATE = 300; // 3% 平台手续费 (基点)
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // 主网地址

    // ============ 事件 ============
    event EventCreated(uint256 indexed eventId, string tokenSymbol, uint256 basePrice, uint256 endTime);
    event BetPlaced(uint256 indexed eventId, address indexed user, bool isYes, uint256 amount, uint256 shares);
    event EarlySettled(uint256 indexed eventId, address indexed user, uint256 amount, uint256 pnl);
    event EventResolved(uint256 indexed eventId, uint256 finalPrice, bool yesWins);
    event RewardsClaimed(uint256 indexed eventId, address indexed user, uint256 amount);

    // ============ 错误 ============
    error InvalidAmount();
    error EventNotActive();
    error BettingEnded();
    error NoRewards();

    // ============ 枚举 ============
    enum EventStatus {
        ACTIVE,
        RESOLVED,
        CANCELLED
    }

    // ============ 数据结构 ============
    struct Event {
        string tokenSymbol;       // 代币符号
        uint256 basePrice;        // 基准价格
        uint256 finalPrice;       // 结算价格
        uint256 endTime;          // 结算时间
        uint256 yesPool;          // YES 池子
        uint256 noPool;           // NO 池子
        uint256 totalPool;        // 总池子
        uint256 totalFees;        // 手续费
        bool yesWins;             // YES 是否获胜
        EventStatus status;       // 事件状态
        bool initialized;         // 是否已初始化
    }

    struct UserBet {
        uint256 amount;           // 总下注金额
        uint256 shares;           // 总份额
        bool isYes;               // 投注方向
        bool claimed;             // 是否已领取
    }

    // ============ 状态变量 ============
    uint256 private _nextEventId;
    mapping(uint256 => Event) public events;
    mapping(uint256 => mapping(address => UserBet)) public userBets;
    mapping(uint256 => address[]) public eventUsers;
    mapping(uint256 => mapping(address => bool)) public hasParticipated;

    address public feeRecipient;
    address public owner;

    // ============ 修饰符 ============
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ============ 构造函数 ============
    constructor(address _feeRecipient) {
        owner = msg.sender;
        feeRecipient = _feeRecipient;
        _nextEventId = 1;
    }

    // ============ 核心功能: 创建事件 ============
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
    }

    // ============ 核心功能: 下注 ============
    function placeBet(
        uint256 eventId,
        bool isYes,
        uint256 amount
    ) external nonReentrant {
        require(amount > 0, "Amount must be > 0");

        Event storage evt = _getEvent(eventId);
        require(evt.status == EventStatus.ACTIVE, "Event not active");
        require(block.timestamp < evt.endTime, "Betting ended");

        // 接收 USDC
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);

        // 计算本次下注的份额
        uint256 shares = _calculateShares(amount, evt.yesPool, evt.noPool, isYes);

        // 更新池子
        if (isYes) {
            evt.yesPool += amount;
        } else {
            evt.noPool += amount;
        }
        evt.totalPool += amount;

        // 记录用户首次参与
        if (!hasParticipated[eventId][msg.sender]) {
            hasParticipated[eventId][msg.sender] = true;
            eventUsers[eventId].push(msg.sender);
        }

        // 聚合下注：重新计算用户在当前池子下的总份额
        _aggregateBet(evt, eventId, msg.sender, isYes, amount, shares);

        emit BetPlaced(eventId, msg.sender, isYes, amount, shares);
    }

    // ============ 聚合下注 ============
    function _aggregateBet(
        Event storage evt,
        uint256 eventId,
        address user,
        bool isYes,
        uint256 amount,
        uint256 newShares
    ) internal {
        UserBet storage bet = userBets[eventId][user];

        if (bet.amount == 0) {
            // 首次下注
            bet.amount = amount;
            bet.shares = newShares;
            bet.isYes = isYes;
            bet.claimed = false;
        } else {
            // 聚合下注：需要重新计算总份额
            // 移除之前金额对池子的影响
            if (bet.isYes) {
                evt.yesPool -= bet.amount;
            } else {
                evt.noPool -= bet.amount;
            }
            evt.totalPool -= bet.amount;

            // 更新总金额
            uint256 newTotalAmount = bet.amount + amount;

            // 在当前池子基础上重新计算总份额
            // CPMM: shares = totalAmount * totalPool / (currentPool + totalAmount)
            uint256 currentPool = isYes ? evt.yesPool : evt.noPool;
            uint256 totalPool = evt.yesPool + evt.noPool;

            if (currentPool == 0) {
                // 对方池为空，直接用金额作为份额
                bet.shares = newTotalAmount;
            } else {
                bet.shares = (newTotalAmount * totalPool) / (currentPool + newTotalAmount);
            }

            // 添加新金额到池子
            if (isYes) {
                evt.yesPool += newTotalAmount;
            } else {
                evt.noPool += newTotalAmount;
            }
            evt.totalPool += newTotalAmount;

            bet.amount = newTotalAmount;
            bet.isYes = isYes;
        }
    }

    // ============ 核心功能: 结算事件 ============
    function resolveEvent(uint256 eventId, uint256 finalPrice) external onlyOwner {
        Event storage evt = _getEvent(eventId);
        require(evt.status == EventStatus.ACTIVE, "Event not active");
        require(block.timestamp >= evt.endTime, "Not ended yet");

        evt.finalPrice = finalPrice;
        evt.yesWins = finalPrice >= evt.basePrice;
        evt.status = EventStatus.RESOLVED;

        emit EventResolved(eventId, finalPrice, evt.yesWins);
    }

    // ============ 核心功能: 批量结算 ============
    function batchResolve(uint256[] calldata eventIds, uint256[] calldata finalPrices) external onlyOwner {
        require(eventIds.length == finalPrices.length, "Length mismatch");
        for (uint256 i = 0; i < eventIds.length; i++) {
            Event storage evt = _getEvent(eventIds[i]);
            require(evt.status == EventStatus.ACTIVE, "Event not active");
            require(block.timestamp >= evt.endTime, "Not ended yet");

            evt.finalPrice = finalPrices[i];
            evt.yesWins = finalPrices[i] >= evt.basePrice;
            evt.status = EventStatus.RESOLVED;

            emit EventResolved(eventIds[i], finalPrices[i], evt.yesWins);
        }
    }

    // ============ 核心功能: 提前平仓 ============
    function earlySettle(uint256 eventId) external nonReentrant {
        Event storage evt = _getEvent(eventId);
        require(evt.status == EventStatus.ACTIVE, "Event not active");
        require(block.timestamp < evt.endTime, "Betting ended");

        UserBet storage bet = userBets[eventId][msg.sender];
        require(bet.amount > 0 && !bet.claimed, "No bet or already settled");

        // 计算 payout
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

        // 从池子中扣除
        if (bet.isYes) {
            evt.yesPool -= bet.amount;
        } else {
            evt.noPool -= bet.amount;
        }
        evt.totalPool -= bet.amount;

        bet.claimed = true;
        IERC20(USDC).safeTransfer(msg.sender, payout);

        emit EarlySettled(eventId, msg.sender, bet.amount, payout - bet.amount - fee);
    }

    // ============ 核心功能: 领取奖励 ============
    function claimRewards(uint256 eventId) external nonReentrant {
        Event storage evt = _getEvent(eventId);
        require(evt.status == EventStatus.RESOLVED, "Not resolved");

        UserBet storage bet = userBets[eventId][msg.sender];
        require(bet.amount > 0, "No bet");
        require(!bet.claimed, "Already claimed");

        bool isWinner = (evt.yesWins && bet.isYes) || (!evt.yesWins && !bet.isYes);
        require(isWinner, "You lost");

        // 计算 payout
        uint256 winningPool = evt.yesWins ? evt.yesPool : evt.noPool;
        uint256 losingPool = evt.yesWins ? evt.noPool : evt.yesPool;
        uint256 payout = _calculatePayout(bet.amount, bet.shares, winningPool, losingPool);

        uint256 fee = (payout - bet.amount) * FEE_RATE / 10000;
        evt.totalFees += fee;
        payout -= fee;

        // 从池子中扣除
        if (bet.isYes) {
            evt.yesPool -= bet.amount;
        } else {
            evt.noPool -= bet.amount;
        }
        evt.totalPool -= bet.amount;

        bet.claimed = true;
        IERC20(USDC).safeTransfer(msg.sender, payout);

        emit RewardsClaimed(eventId, msg.sender, payout);
    }

    // ============ 管理员函数 ============
    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "Zero address");
        feeRecipient = recipient;
    }

    function rescueToken(uint256 amount) external onlyOwner {
        IERC20(USDC).safeTransfer(msg.sender, amount);
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
            bool isWinner = (evt.yesWins && bet.isYes) || (!evt.yesWins && !bet.isYes);
            if (isWinner) {
                uint256 winningPool = evt.yesWins ? evt.yesPool : evt.noPool;
                uint256 losingPool = evt.yesWins ? evt.noPool : evt.yesPool;
                payout = _calculatePayout(bet.amount, bet.shares, winningPool, losingPool);
            }
        }
    }

    // ============ 内部函数 ============
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
}
