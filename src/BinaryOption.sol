// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPredictionEvent} from "./interfaces/IPredictionEvent.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {BinaryOptionMath} from "./libraries/BinaryOptionMath.sol";
import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title BinaryOption
 * @dev 单个二元期权事件合约
 */
contract BinaryOption is IPredictionEvent, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // 事件定义
    event EventCreated(
        address indexed eventAddress,
        string indexed tokenSymbol,
        uint256 duration,
        uint256 targetPrice,
        uint256 timestamp
    );

    // 状态变量
    Event public eventInfo;
    Phase public currentPhase = Phase.OPEN;

    // 用户下注记录
    mapping(address => Bet[]) public userBets;
    mapping(address => uint256) public userTotalYesAmount;
    mapping(address => uint256) public userTotalNoAmount;

    // 系统配置
    address public priceOracle;
    address public aiOracle;
    address public treasury;
    uint256 public platformFee = 300; // 3% (基点)

    uint256 public constant PRECISION = 10000; // Used for fixed-point arithmetic, e.g., for platformFee (basis points)

    // 限制参数
    uint256 public minBetAmount = 1e15; // 0.001 ETH/USDT
    uint256 public maxPoolSize = 1000e18; // 1000 ETH/USDT
    uint256 public maxPriceChange = 5000; // 50% (基点)

    // 支持的代币 (ETH地址为0)
    mapping(address => bool) public supportedTokens;

    // 统计数据
    uint256 public totalBetsCount;
    uint256 public totalVolume;
    uint256 public totalFeesCollected;

    // Internal check functions
    function _checkWhenOpen() private view {
        if (currentPhase != Phase.OPEN) revert Errors.BettingNotActive();
    }

    function _checkWhenLocked() private view {
        if (currentPhase != Phase.LOCKED) revert Errors.EventNotLocked();
    }

    function _checkWhenSettled() private view {
        if (currentPhase != Phase.SETTLED) revert Errors.EventNotSettled();
    }

    function _checkValidPhase() private view {
        if (currentPhase == Phase.CANCELLED)
            revert Errors.EventAlreadyCancelled();
    }

    function _checkValidPosition(Position position) private pure {
        if (position != Position.YES && position != Position.NO)
            revert Errors.InvalidPosition();
    }

    function _checkSupportedToken(address token) private view {
        if (token != address(0) && !supportedTokens[token])
            revert Errors.InvalidParameter();
    }

    // Modifiers
    modifier onlyWhenOpen() {
        _checkWhenOpen();
        _;
    }

    modifier onlyWhenLocked() {
        _checkWhenLocked();
        _;
    }

    modifier onlyWhenSettled() {
        _checkWhenSettled();
        _;
    }

    modifier validPhase() {
        _checkValidPhase();
        _;
    }

    modifier validPosition(Position position) {
        _checkValidPosition(position);
        _;
    }

    modifier supportedToken(address token) {
        _checkSupportedToken(token);
        _;
    }

    constructor(
        EventParams memory params,
        address _priceOracle,
        address _aiOracle,
        address _treasury,
        address[] memory _supportedTokens
    ) Ownable(msg.sender) {
        require(params.startTime >= block.timestamp, Errors.InvalidTimestamp());
        require(params.endTime > params.startTime, Errors.InvalidDuration());
        require(
            params.duration == params.endTime - params.startTime,
            Errors.InvalidDuration()
        );
        require(
            params.duration >= 5 minutes && params.duration <= 24 hours,
            Errors.InvalidDuration()
        );
        require(params.strikePrice > 0, Errors.InvalidAmount());
        require(params.targetPrice > 0, Errors.InvalidAmount());

        // 初始化事件信息
        eventInfo = Event({
            tokenSymbol: params.tokenSymbol,
            priceFeed: params.priceFeed,
            startTime: params.startTime,
            endTime: params.endTime,
            strikePrice: params.strikePrice,
            targetPrice: params.targetPrice,
            tolerance: params.tolerance,
            winningPosition: Position.NO, // 默认值
            currentPhase: Phase.OPEN,
            yesPool: 0,
            noPool: 0,
            totalPool: 0,
            exists: true
        });

        priceOracle = _priceOracle;
        aiOracle = _aiOracle;
        treasury = _treasury;

        // 设置支持的代币
        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            supportedTokens[_supportedTokens[i]] = true;
        }

        // 默认支持ETH (address(0))
        supportedTokens[address(0)] = true;

        // 发出事件创建事件
        emit EventCreated(
            address(this),
            params.tokenSymbol,
            params.duration,
            params.targetPrice,
            block.timestamp
        );
    }

    /**
     * @dev 初始化克隆合约
     */
    function initialize(
        EventParams memory params,
        address _priceOracle,
        address _aiOracle,
        address _treasury,
        address[] memory _supportedTokens
    ) external {
        require(!eventInfo.exists, "Already initialized");
        require(params.startTime >= block.timestamp, Errors.InvalidTimestamp());
        require(params.endTime > params.startTime, Errors.InvalidDuration());
        require(
            params.duration == params.endTime - params.startTime,
            Errors.InvalidDuration()
        );
        require(
            params.duration >= 5 minutes && params.duration <= 24 hours,
            Errors.InvalidDuration()
        );
        require(params.strikePrice > 0, Errors.InvalidAmount());
        require(params.targetPrice > 0, Errors.InvalidAmount());

        // 初始化事件信息
        eventInfo = Event({
            tokenSymbol: params.tokenSymbol,
            priceFeed: params.priceFeed,
            startTime: params.startTime,
            endTime: params.endTime,
            strikePrice: params.strikePrice,
            targetPrice: params.targetPrice,
            tolerance: params.tolerance,
            winningPosition: Position.NO, // 默认值
            currentPhase: Phase.OPEN,
            yesPool: 0,
            noPool: 0,
            totalPool: 0,
            exists: true
        });

        priceOracle = _priceOracle;
        aiOracle = _aiOracle;
        treasury = _treasury;

        // 设置支持的代币
        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            supportedTokens[_supportedTokens[i]] = true;
        }

        // 默认支持ETH (address(0))
        supportedTokens[address(0)] = true;

        // 发出事件创建事件
        emit EventCreated(
            address(this),
            params.tokenSymbol,
            params.duration,
            params.targetPrice,
            block.timestamp
        );
    }

    /**
     * @dev 下注 (接口实现)
     * @param position 位置 (YES/NO)
     * @param amount 下注金额
     */
    function placeBet(
        Position position,
        uint256 amount
    )
        external
        payable
        override
        nonReentrant
        onlyWhenOpen
        validPosition(position)
    {
        address token = address(0); // ETH
        if (msg.value != amount) revert Errors.InvalidAmount();
        _placeBetInternal(position, amount, token);
    }

    /**
     * @dev 下注 (内部函数，支持多代币)
     * @param position 位置 (YES/NO)
     * @param amount 下注金额
     * @param token 代币地址 (ETH使用address(0))
     */
    function _placeBetInternal(
        Position position,
        uint256 amount,
        address token
    ) internal supportedToken(token) {
        if (amount < minBetAmount) revert Errors.BetAmountTooLow();
        if (amount > maxPoolSize) revert Errors.BetAmountTooHigh();
        if (block.timestamp < eventInfo.startTime)
            revert Errors.BettingNotStarted();
        if (block.timestamp >= eventInfo.endTime) revert Errors.BettingEnded();

        // 检查支付
        if (token == address(0)) {
            // ETH支付
            if (msg.value != amount) revert Errors.InvalidAmount();
        } else {
            // ERC20代币支付
            if (msg.value != 0) revert Errors.InvalidAmount();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // 更新池子大小
        if (position == Position.YES) {
            eventInfo.yesPool += amount;
            userTotalYesAmount[msg.sender] += amount;
        } else {
            eventInfo.noPool += amount;
            userTotalNoAmount[msg.sender] += amount;
        }

        eventInfo.totalPool += amount;
        totalVolume += amount;

        // 记录下注
        userBets[msg.sender].push(
            Bet({
                user: msg.sender,
                position: position,
                amount: amount,
                timestamp: block.timestamp,
                claimed: false
            })
        );

        totalBetsCount++;

        // 检查是否达到最大池子大小
        if (eventInfo.totalPool >= maxPoolSize) {
            _lockEvent();
        }

        emit BetPlaced(msg.sender, position, amount);
        emit Events.BetPlaced(
            msg.sender,
            address(this),
            uint256(position),
            amount,
            block.timestamp
        );
    }

    /**
     * @dev 结算事件
     */
    function settle() external override nonReentrant validPhase {
        if (currentPhase != Phase.OPEN && currentPhase != Phase.LOCKED) {
            revert Errors.EventNotSettled();
        }

        if (block.timestamp < eventInfo.endTime) {
            revert Errors.EventNotEnded();
        }

        // 获取最终价格
        (uint256 finalPrice, ) = IPriceOracle(priceOracle).getPrice(
            eventInfo.priceFeed
        );
        if (finalPrice == 0) revert Errors.PriceNotAvailable();

        // 确定获胜方
        eventInfo.winningPosition = _determineWinner(finalPrice);
        currentPhase = Phase.SETTLED;
        eventInfo.currentPhase = Phase.SETTLED;

        emit EventSettled(eventInfo.winningPosition, finalPrice);
        emit Events.EventSettled(
            address(this),
            uint256(eventInfo.winningPosition),
            finalPrice,
            eventInfo.totalPool,
            block.timestamp
        );
    }

    /**
     * @dev 领取奖金
     */
    function claimWinnings() external override nonReentrant onlyWhenSettled {
        if (userBets[msg.sender].length == 0) revert Errors.BetNotFound();

        uint256 totalWinnings = _calculateUserWinnings(msg.sender);
        if (totalWinnings == 0) revert Errors.NoWinningsToClaim();

        // 标记为已领取
        for (uint256 i = 0; i < userBets[msg.sender].length; i++) {
            userBets[msg.sender][i].claimed = true;
        }

        // 计算平台费用
        uint256 platformFees = (totalWinnings * platformFee) /
            (PRECISION + platformFee);
        uint256 userPayout = totalWinnings - platformFees;

        // 转账给用户
        if (address(this).balance >= userPayout) {
            payable(msg.sender).transfer(userPayout);
        } else {
            // 如果ETH余额不足，使用ERC20代币
            // 这里简化处理，实际应该记录用户使用的代币类型
            revert Errors.InsufficientBalance();
        }

        // 收取费用
        if (platformFees > 0) {
            totalFeesCollected += platformFees;
            payable(treasury).transfer(platformFees);
        }

        emit WinningsClaimed(msg.sender, userPayout);
        emit Events.WinningsClaimed(
            msg.sender,
            address(this),
            userPayout,
            block.timestamp
        );
    }

    /**
     * @dev 取消事件
     */
    function cancelEvent(
        string calldata reason
    ) external override onlyOwner validPhase {
        currentPhase = Phase.CANCELLED;
        eventInfo.currentPhase = Phase.CANCELLED;

        // 退款给所有用户
        _refundAllUsers();

        emit EventCancelled(reason);
        emit Events.EventCancelled(address(this), reason, block.timestamp);
    }

    /**
     * @dev 锁定事件
     */
    function _lockEvent() internal {
        currentPhase = Phase.LOCKED;
        eventInfo.currentPhase = Phase.LOCKED;
        emit EventLocked();
        emit Events.EventLocked(address(this), block.timestamp);
    }

    /**
     * @dev 确定获胜方
     */
    function _determineWinner(
        uint256 finalPrice
    ) internal view returns (Position) {
        // 这里简化处理，实际应该根据不同的期权类型来判断
        if (finalPrice >= eventInfo.targetPrice) {
            return Position.YES;
        } else {
            return Position.NO;
        }
    }

    /**
     * @dev 计算用户获胜金额
     */
    function _calculateUserWinnings(
        address user
    ) internal view returns (uint256) {
        uint256 winningAmount = 0;

        if (eventInfo.winningPosition == Position.YES) {
            winningAmount = userTotalYesAmount[user];
        } else {
            winningAmount = userTotalNoAmount[user];
        }

        if (winningAmount == 0) return 0;

        (uint256 yesOdds, uint256 noOdds) = BinaryOptionMath.calculateOdds(
            eventInfo.yesPool,
            eventInfo.noPool,
            platformFee
        );
        uint256 odds = eventInfo.winningPosition == Position.YES
            ? yesOdds
            : noOdds;

        return BinaryOptionMath.calculateWinnings(winningAmount, odds);
    }

    /**
     * @dev 退款给所有用户
     */
    function _refundAllUsers() internal {
        // 简化处理，实际需要遍历所有用户
        // 可以维护一个用户列表来优化
    }

    /**
     * @dev 获取当前赔率
     */
    function getCurrentOdds()
        external
        view
        override
        returns (uint256 yesOdds, uint256 noOdds)
    {
        return
            BinaryOptionMath.calculateOdds(
                eventInfo.yesPool,
                eventInfo.noPool,
                platformFee
            );
    }

    /**
     * @dev 获取用户获胜金额
     */
    function getUserWinnings(
        address user
    ) external view override returns (uint256) {
        if (currentPhase != Phase.SETTLED) return 0;
        return _calculateUserWinnings(user);
    }

    /**
     * @dev 获取用户下注记录
     */
    function getUserBets(
        address user
    ) external view override returns (Bet[] memory) {
        return userBets[user];
    }

    /**
     * @dev 获取事件信息
     */
    function getEventInfo() external view override returns (Event memory) {
        return eventInfo;
    }

    /**
     * @dev 设置平台费用 (仅Owner)
     */
    function setPlatformFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, Errors.InvalidParameter()); // 最大10%
        platformFee = newFee;
    }

    /**
     * @dev 设置下注限制 (仅Owner)
     */
    function setBettingLimits(
        uint256 minBet,
        uint256 maxPool
    ) external onlyOwner {
        minBetAmount = minBet;
        maxPoolSize = maxPool;
    }

    /**
     * @dev 暂停合约 (仅Owner)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 恢复合约 (仅Owner)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 紧急提取 (仅Owner)
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }
}
