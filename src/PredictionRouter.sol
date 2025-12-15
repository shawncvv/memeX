// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPredictionFactory} from "./interfaces/IPredictionFactory.sol";
import {IPredictionEvent} from "./interfaces/IPredictionEvent.sol";
import {IRiskManager} from "./interfaces/IRiskManager.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title PredictionRouter
 * @dev 预测平台路由合约，统一入口
 */
contract PredictionRouter is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // 合约地址
    address public predictionFactory;
    address public priceOracle;
    address public aiOracle;
    address public riskManager;
    address public treasury;

    // 支持的代币
    address[] public supportedTokens;
    mapping(address => bool) public isTokenSupported;

    // AI 支付验证 (X402 协议支付后记录)
    mapping(bytes32 => mapping(address => bool)) public hasAiPayment;

    // 配置参数
    uint256 public maxBatchSize = 20;
    uint256 public minExecutionDelay = 30; // 30秒延迟
    uint256 public platformFee = 300; // 3%

    // 执行计划 (用于延迟执行)
    struct ExecutionPlan {
        address user;
        bytes32[] eventIds;
        IPredictionEvent.Position[] positions;
        uint256[] amounts;
        address[] tokens;
        uint256 executeAt;
        bool executed;
        bool cancelled;
    }

    mapping(bytes32 => ExecutionPlan) public executionPlans;
    mapping(address => bytes32[]) public userExecutionPlans;

    // Modifiers
    modifier onlyValidContract(address contractAddress) {
        _onlyValidContract(contractAddress);
        _;
    }

    function _onlyValidContract(address contractAddress) internal pure {
        require(contractAddress != address(0), Errors.ZeroAddress());
    }

    modifier onlyAiOracle() {
        _onlyAiOracle();
        _;
    }

    function _onlyAiOracle() internal view {
        require(msg.sender == aiOracle, Errors.Unauthorized());
    }

    modifier onlySupportedToken(address token) {
        _onlySupportedToken(token);
        _;
    }

    function _onlySupportedToken(address token) internal view {
        require(
            token == address(0) || isTokenSupported[token],
            TokenNotSupported()
        );
    }

    modifier onlyWhenSystemHealthy() {
        // TODO: 检查所有关键合约状态 - 需要在接口中添加 paused() 函数
        // require(
        //     !IPredictionFactory(predictionFactory).paused(),
        //     Errors.SystemPaused()
        // );
        // require(!IPriceOracle(priceOracle).paused(), Errors.SystemPaused());
        _;
    }

    constructor(
        address _initialOwner,
        address _predictionFactory,
        address _priceOracle,
        address _aiOracle,
        address _riskManager,
        address _treasury
    ) Ownable(_initialOwner) {
        predictionFactory = _predictionFactory;
        priceOracle = _priceOracle;
        aiOracle = _aiOracle;
        riskManager = _riskManager;
        treasury = _treasury;

        // 默认支持ETH
        isTokenSupported[address(0)] = true;
        supportedTokens.push(address(0));
    }

    /**
     * @dev 创建并下注
     */
    function createAndBet(
        IPredictionFactory.EventParams calldata eventParams,
        IPredictionEvent.Position position,
        uint256 betAmount,
        address token,
        bool useAi,
        string calldata /*aiQuestion*/
    )
        external
        payable
        nonReentrant
        onlyWhenSystemHealthy
        onlySupportedToken(token)
        returns (address eventAddress, bytes32 aiRequestId)
    {
        // 1. 风险检查
        (bool isValid, ) = IRiskManager(riskManager)
            .validateEventParameters(eventParams);
        if (!isValid) revert Errors.InvalidRiskParameters();

        // 2. 创建事件
        eventAddress = IPredictionFactory(predictionFactory).createEvent(
            eventParams
        );

        // 3. AI预测 (如果需要)
        if (useAi) {
            // AI 支付由前端通过 X402 协议处理，这里只需要验证支付状态
            bytes32 eventId;
            assembly {
                mstore(0x00, eventAddress)
                eventId := keccak256(0x00, 0x20)
            }
            require(
                hasAiPayment[eventId][msg.sender],
                "AI payment required via X402"
            );
            aiRequestId = keccak256(
                abi.encodePacked(eventId, msg.sender, block.timestamp)
            );
        }

        // 4. 执行下注
        _executeBet(
            eventAddress,
            position,
            betAmount,
            token,
            msg.value > 0 ? msg.value : 0
        );

        emit CreateAndBet(msg.sender, eventAddress, position, betAmount, token);
    }

    /**
     * @dev 智能下注 (基于AI建议)
     */
    function intelligentBet(
        address eventAddress,
        uint256 betAmount,
        address token,
        string calldata /*aiQuestion*/,
        bytes32 aiRequestId // 前端通过X402支付后获取的请求ID
    )
        external
        payable
        nonReentrant
        onlyWhenSystemHealthy
        onlySupportedToken(token)
        returns (IPredictionEvent.Position recommendedPosition)
    {
        // 1. 验证AI支付已通过X402协议完成
        bytes32 eventId;
        assembly {
            mstore(0x00, eventAddress)
            eventId := keccak256(0x00, 0x20)
        }
        require(hasAiPayment[eventId][msg.sender], "AI payment required");

        // 2. 获取AI预测结果 (基于前端通过API获取的结果)
        recommendedPosition = _getAiRecommendation(aiRequestId);

        // 3. 执行下注
        _executeBet(
            eventAddress,
            recommendedPosition,
            betAmount,
            token,
            msg.value > 0 ? msg.value : 0
        );

        emit IntelligentBet(
            msg.sender,
            eventAddress,
            recommendedPosition,
            betAmount,
            token,
            aiRequestId
        );
    }

    /**
     * @dev 批量下注
     */
    function batchBet(
        address[] calldata eventAddresses,
        IPredictionEvent.Position[] calldata positions,
        uint256[] calldata amounts,
        address[] calldata tokens,
        bool[] calldata useAi,
        string[] calldata /*aiQuestions*/
    ) external payable nonReentrant onlyWhenSystemHealthy {
        require(
            eventAddresses.length == positions.length &&
                eventAddresses.length == amounts.length &&
                eventAddresses.length == tokens.length,
            Errors.ArrayLengthMismatch()
        );
        require(
            eventAddresses.length <= maxBatchSize,
            Errors.BatchSizeExceeded()
        );

        uint256 totalEthAmount = _calculateTotalEth(tokens, amounts);
        require(msg.value >= totalEthAmount, Errors.InsufficientPayment());

        // 执行批量操作
        _processBatchBets(eventAddresses, positions, amounts, tokens, useAi);

        emit BatchBet(msg.sender, eventAddresses, positions, amounts, tokens);
    }

    /**
     * @dev 计划批量执行 (延迟执行)
     */
    function planBatchExecution(
        address[] calldata eventAddresses,
        IPredictionEvent.Position[] calldata positions,
        uint256[] calldata amounts,
        address[] calldata tokens,
        uint256 delaySeconds
    ) external returns (bytes32 planId) {
        require(
            eventAddresses.length == positions.length &&
                eventAddresses.length == amounts.length &&
                eventAddresses.length == tokens.length,
            Errors.ArrayLengthMismatch()
        );
        require(delaySeconds >= minExecutionDelay, Errors.InvalidDuration());

        planId = keccak256(
            abi.encodePacked(
                msg.sender,
                eventAddresses,
                positions,
                amounts,
                tokens,
                block.timestamp
            )
        );

        executionPlans[planId] = ExecutionPlan({
            user: msg.sender,
            eventIds: new bytes32[](eventAddresses.length),
            positions: positions,
            amounts: amounts,
            tokens: tokens,
            executeAt: block.timestamp + delaySeconds,
            executed: false,
            cancelled: false
        });

        // 转换事件地址为事件ID
        for (uint256 i = 0; i < eventAddresses.length; i++) {
            executionPlans[planId].eventIds[i] = keccak256(
                abi.encodePacked(eventAddresses[i])
            );
        }

        userExecutionPlans[msg.sender].push(planId);

        emit BatchExecutionPlanned(
            msg.sender,
            planId,
            eventAddresses,
            delaySeconds
        );
    }

    /**
     * @dev 执行计划
     */
    function executePlan(
        bytes32 planId
    ) external payable nonReentrant onlyWhenSystemHealthy {
        ExecutionPlan storage plan = executionPlans[planId];
        require(plan.user == msg.sender, Errors.Unauthorized());
        require(!plan.executed, PlanAlreadyExecuted());
        require(!plan.cancelled, PlanCancelled());
        require(block.timestamp >= plan.executeAt, ExecutionNotReady());

        uint256 totalEthAmount = 0;

        // 计算总ETH需求
        for (uint256 i = 0; i < plan.tokens.length; i++) {
            if (plan.tokens[i] == address(0)) {
                totalEthAmount += plan.amounts[i];
            }
        }

        require(msg.value >= totalEthAmount, Errors.InsufficientPayment());

        // 执行下注
        for (uint256 i = 0; i < plan.eventIds.length; i++) {
            address eventAddress = address(uint160(uint256(plan.eventIds[i])));
            _executeBet(
                eventAddress,
                plan.positions[i],
                plan.amounts[i],
                plan.tokens[i],
                plan.tokens[i] == address(0) ? plan.amounts[i] : 0
            );
        }

        plan.executed = true;

        emit BatchExecutionExecuted(msg.sender, planId);
    }

    /**
     * @dev 取消计划
     */
    function cancelPlan(bytes32 planId) external {
        ExecutionPlan storage plan = executionPlans[planId];
        require(plan.user == msg.sender, Errors.Unauthorized());
        require(!plan.executed, PlanAlreadyExecuted());
        require(!plan.cancelled, PlanCancelled());

        plan.cancelled = true;

        emit BatchExecutionCancelled(msg.sender, planId);
    }

    /**
     * @dev 快速结算所有已完成的事件
     */
    function quickSettleEvents(address[] calldata eventAddresses) external {
        require(eventAddresses.length <= 50, Errors.BatchSizeExceeded());

        for (uint256 i = 0; i < eventAddresses.length; i++) {
            try IPredictionEvent(eventAddresses[i]).settle() {
                // 成功结算
                emit EventSettled(eventAddresses[i]);
            } catch {
                // 结算失败，记录错误
                emit EventSettlementFailed(eventAddresses[i]);
            }
        }
    }

    /**
     * @dev 批量领取奖金
     */
    function batchClaimWinnings(address[] calldata eventAddresses) external {
        for (uint256 i = 0; i < eventAddresses.length; i++) {
            try IPredictionEvent(eventAddresses[i]).claimWinnings() {
                // 成功领取
                emit WinningsClaimed(msg.sender, eventAddresses[i], 0);
            } catch {
                // 领取失败，可能是没有奖金
                emit WinningsClaimFailed(msg.sender, eventAddresses[i]);
            }
        }
    }

    /**
     * @dev 获取用户活跃事件
     */
    function getUserActiveEvents(
        address user
    ) external view returns (address[] memory) {
        // 这里需要遍历所有事件来查找用户参与的
        // 在实际应用中可能需要优化数据结构
        address[] memory allEvents = IPredictionFactory(predictionFactory)
            .getActiveEvents();
        uint256 count = 0;

        // 先计算数量
        for (uint256 i = 0; i < allEvents.length; i++) {
            try IPredictionEvent(allEvents[i]).getUserBets(user) returns (
                IPredictionEvent.Bet[] memory bets
            ) {
                if (bets.length > 0) {
                    count++;
                }
            } catch {
                continue;
            }
        }

        // 填充结果
        address[] memory userEvents = new address[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < allEvents.length; i++) {
            try IPredictionEvent(allEvents[i]).getUserBets(user) returns (
                IPredictionEvent.Bet[] memory bets
            ) {
                if (bets.length > 0) {
                    userEvents[index] = allEvents[i];
                    index++;
                }
            } catch {
                continue;
            }
        }

        return userEvents;
    }

    /**
     * @dev 记录 X402 AI 支付完成 (由 AI Oracle 调用)
     */
    function recordAiPayment(
        bytes32 eventId,
        address user,
        bytes32 aiRequestId
    ) external onlyAiOracle {
        hasAiPayment[eventId][user] = true;
        emit AIPaymentRecorded(eventId, user, aiRequestId);
    }

    /**
     * @dev 设置支持的代币
     */
    function setSupportedToken(
        address token,
        bool supported
    ) external onlyOwner {
        require(token != address(0), Errors.ZeroAddress());

        if (supported && !isTokenSupported[token]) {
            supportedTokens.push(token);
            isTokenSupported[token] = true;
        } else if (!supported && isTokenSupported[token]) {
            isTokenSupported[token] = false;
            // 从数组中移除
            for (uint256 i = 0; i < supportedTokens.length; i++) {
                if (supportedTokens[i] == token) {
                    supportedTokens[i] = supportedTokens[
                        supportedTokens.length - 1
                    ];
                    supportedTokens.pop();
                    break;
                }
            }
        }
    }

    /**
     * @dev 设置合约地址
     */
    function setContractAddress(
        string calldata contractName,
        address contractAddress
    ) external onlyOwner onlyValidContract(contractAddress) {
        if (
            keccak256(bytes(contractName)) ==
            keccak256(bytes("PredictionFactory"))
        ) {
            predictionFactory = contractAddress;
        } else if (
            keccak256(bytes(contractName)) == keccak256(bytes("PriceOracle"))
        ) {
            priceOracle = contractAddress;
        } else if (
            keccak256(bytes(contractName)) == keccak256(bytes("AIOracle"))
        ) {
            aiOracle = contractAddress;
        } else if (
            keccak256(bytes(contractName)) == keccak256(bytes("RiskManager"))
        ) {
            riskManager = contractAddress;
        } else if (
            keccak256(bytes(contractName)) == keccak256(bytes("Treasury"))
        ) {
            treasury = contractAddress;
        } else {
            revert InvalidContractName();
        }
    }

    /**
     * @dev 设置配置参数
     */
    function setConfiguration(
        uint256 _maxBatchSize,
        uint256 _minExecutionDelay,
        uint256 _platformFee
    ) external onlyOwner {
        require(_maxBatchSize > 0, Errors.InvalidParameter());
        require(_minExecutionDelay > 0, Errors.InvalidParameter());
        require(_platformFee <= 1000, Errors.InvalidParameter()); // 最大10%

        maxBatchSize = _maxBatchSize;
        minExecutionDelay = _minExecutionDelay;
        platformFee = _platformFee;
    }

    /**
     * @dev 计算总ETH数量 (内部函数)
     */
    function _calculateTotalEth(
        address[] calldata tokens,
        uint256[] calldata amounts
    ) internal pure returns (uint256 totalEthAmount) {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ) {
            if (tokens[i] == address(0)) {
                totalEthAmount += amounts[i];
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev 处理批量下注 (内部函数)
     */
    function _processBatchBets(
        address[] calldata eventAddresses,
        IPredictionEvent.Position[] calldata positions,
        uint256[] calldata amounts,
        address[] calldata tokens,
        bool[] calldata useAi
    ) internal {
        uint256 length = eventAddresses.length;
        for (uint256 i = 0; i < length; ) {
            if (useAi[i]) {
                _verifyAiPayment(eventAddresses[i]);
            }

            _executeBet(
                eventAddresses[i],
                positions[i],
                amounts[i],
                tokens[i],
                tokens[i] == address(0) ? amounts[i] : 0
            );

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev 验证AI支付 (内部函数)
     */
    function _verifyAiPayment(address eventAddress) internal view {
        bytes32 eventId;
        assembly {
            mstore(0x00, eventAddress)
            eventId := keccak256(0x00, 0x20)
        }
        require(
            hasAiPayment[eventId][msg.sender],
            "AI payment required via X402"
        );
    }

    /**
     * @dev 执行下注 (内部函数)
     */
    function _executeBet(
        address eventAddress,
        IPredictionEvent.Position position,
        uint256 amount,
        address token,
        uint256 ethValue
    ) internal {
        // 检查用户权限
        (bool isValid, ) = IRiskManager(riskManager)
            .validateUserBet(
                msg.sender,
                amount,
                0, // 当前池子大小需要在事件合约中获取
                token
            );

        if (!isValid) revert Errors.InvalidRiskParameters();

        // 执行下注
        if (token == address(0)) {
            // ETH下注
            IPredictionEvent(eventAddress).placeBet{value: ethValue}(
                position,
                amount
            );
        } else {
            // ERC20下注
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(token).safeTransfer(eventAddress, amount);
            IPredictionEvent(eventAddress).placeBet(position, amount);
        }

        emit BetExecuted(msg.sender, eventAddress, position, amount, token);
    }

    /**
     * @dev 获取AI建议 (模拟)
     */
    function _getAiRecommendation(
        bytes32 /*aiRequestId*/
    ) internal pure returns (IPredictionEvent.Position) {
        // 在实际应用中，这里会调用AI服务获取建议
        // 这里简化返回YES
        return IPredictionEvent.Position.YES;
    }

    // 事件定义
    event CreateAndBet(
        address indexed user,
        address indexed eventAddress,
        IPredictionEvent.Position position,
        uint256 amount,
        address indexed token
    );

    event IntelligentBet(
        address indexed user,
        address indexed eventAddress,
        IPredictionEvent.Position position,
        uint256 amount,
        address indexed token,
        bytes32 aiRequestId
    );

    event AIPaymentRecorded(
        bytes32 indexed eventId,
        address indexed user,
        bytes32 aiRequestId
    );

    event BatchBet(
        address indexed user,
        address[] eventAddresses,
        IPredictionEvent.Position[] positions,
        uint256[] amounts,
        address[] tokens
    );

    event BatchExecutionPlanned(
        address indexed user,
        bytes32 indexed planId,
        address[] eventAddresses,
        uint256 delay
    );

    event BatchExecutionExecuted(address indexed user, bytes32 indexed planId);

    event BatchExecutionCancelled(address indexed user, bytes32 indexed planId);

    event EventSettled(address indexed eventAddress);
    event EventSettlementFailed(address indexed eventAddress);
    event WinningsClaimed(
        address indexed user,
        address indexed eventAddress,
        uint256 amount
    );
    event WinningsClaimFailed(
        address indexed user,
        address indexed eventAddress
    );
    event BetExecuted(
        address indexed user,
        address indexed eventAddress,
        IPredictionEvent.Position position,
        uint256 amount,
        address indexed token
    );

    // 错误定义
    error TokenNotSupported();
    error InvalidContractName();
    error PlanAlreadyExecuted();
    error PlanCancelled();
    error ExecutionNotReady();
}
