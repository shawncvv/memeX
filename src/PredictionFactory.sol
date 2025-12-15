// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IPredictionFactory} from "./interfaces/IPredictionFactory.sol";
import {IPredictionEvent} from "./interfaces/IPredictionEvent.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {Errors as CustomErrors} from "./libraries/Errors.sol";

/**
 * @title PredictionFactory
 * @dev 预测事件工厂合约
 */
contract PredictionFactory is
    IPredictionFactory,
    ReentrancyGuard,
    Pausable,
    Ownable
{
    // 状态变量
    address public binaryOptionImplementation;
    address[] public activeEvents;

    // 映射
    mapping(address => bool) public isEventActive;
    mapping(string => address[]) public eventsByToken;
    mapping(address => uint256) public eventIndex;

    // 配置
    address public priceOracle;
    address public aiOracle;
    address public treasury;
    address public riskManager;

    bool public eventCreationEnabled = true;
    uint256 public maxEventsPerToken = 10;
    uint256 public maxActiveEvents = 100;

    // 统计
    uint256 public totalEventsCreated;
    uint256 public totalActiveEvents;

    // 事件模板支持的代币
    address[] public supportedTokens;

    // Internal check functions
    function _checkWhenEnabled() private view {
        if (!eventCreationEnabled) revert CustomErrors.EventCreationDisabled();
    }

    function _checkValidEventParams(EventParams calldata params) private pure {
        if (bytes(params.tokenSymbol).length == 0) revert CustomErrors.EmptyString();
        if (params.priceFeed == address(0)) revert CustomErrors.ZeroAddress();
        if (params.duration < 5 minutes || params.duration > 24 hours)
            revert CustomErrors.InvalidDuration();
        if (params.strikePrice == 0 || params.targetPrice == 0)
            revert CustomErrors.InvalidAmount();
    }

    function _checkRiskManager() private view {
        require(msg.sender == riskManager, "Unauthorized");
    }

    // Modifiers
    modifier onlyWhenEnabled() {
        _checkWhenEnabled();
        _;
    }

    modifier validEventParams(EventParams calldata params) {
        _checkValidEventParams(params);
        _;
    }

    modifier onlyRiskManager() {
        _checkRiskManager();
        _;
    }

    constructor(
        address _binaryOptionImplementation,
        address _priceOracle,
        address _aiOracle,
        address _treasury,
        address[] memory _supportedTokens
    ) Ownable(msg.sender) {
        binaryOptionImplementation = _binaryOptionImplementation;
        priceOracle = _priceOracle;
        aiOracle = _aiOracle;
        treasury = _treasury;
        supportedTokens = _supportedTokens;
    }

    /**
     * @dev 创建新的预测事件
     * @param params 事件参数
     * @return eventAddress 新事件的地址
     */
    function createEvent(
        EventParams calldata params
    )
        external
        override
        nonReentrant
        onlyWhenEnabled
        validEventParams(params)
        returns (address eventAddress)
    {
        // 检查是否达到最大事件数限制
        if (totalActiveEvents >= maxActiveEvents) {
            revert CustomErrors.PoolSizeExceeded();
        }

        // 检查单个代币的事件数限制
        if (eventsByToken[params.tokenSymbol].length >= maxEventsPerToken) {
            revert CustomErrors.BatchSizeExceeded();
        }

        // 验证价格预言机
        if (!IPriceOracle(priceOracle).isTokenSupported(params.priceFeed)) {
            revert CustomErrors.InvalidPriceFeed();
        }

        // 创建事件合约
        eventAddress = Clones.clone(binaryOptionImplementation);

        // 准备参数
        IPredictionEvent.EventParams memory eventParams = IPredictionEvent
            .EventParams({
                tokenSymbol: params.tokenSymbol,
                priceFeed: params.priceFeed,
                duration: params.duration,
                strikePrice: params.strikePrice,
                targetPrice: params.targetPrice,
                tolerance: params.tolerance,
                startTime: block.timestamp,
                endTime: block.timestamp + params.duration
            });

        // 初始化事件合约
        IPredictionEvent(eventAddress).initialize(
            eventParams,
            priceOracle,
            aiOracle,
            treasury,
            supportedTokens
        );

        // 记录事件
        _recordEvent(eventAddress, params.tokenSymbol);

        // 发出事件
        emit EventCreated(
            eventAddress,
            params.tokenSymbol,
            params.duration,
            params.targetPrice
        );

        return eventAddress;
    }

    /**
     * @dev 获取所有活跃事件
     */
    function getActiveEvents()
        external
        view
        override
        returns (address[] memory)
    {
        address[] memory result = new address[](totalActiveEvents);
        uint256 index = 0;

        for (uint256 i = 0; i < activeEvents.length; i++) {
            if (isEventActive[activeEvents[i]]) {
                result[index] = activeEvents[i];
                index++;
            }
        }

        // 调整数组大小
        assembly {
            mstore(result, index)
        }

        return result;
    }

    /**
     * @dev 根据代币符号获取事件
     */
    function getEventsByToken(
        string calldata tokenSymbol
    ) external view override returns (address[] memory) {
        return eventsByToken[tokenSymbol];
    }

    /**
     * @dev 检查事件是否活跃
     */
    function checkEventActive(
        address eventAddress
    ) external view override returns (bool) {
        return isEventActive[eventAddress];
    }

    /**
     * @dev 切换事件创建状态
     */
    function toggleEventCreation() external override onlyOwner {
        eventCreationEnabled = !eventCreationEnabled;
        emit EventCreationToggled(eventCreationEnabled);
    }

    /**
     * @dev 更新事件模板
     */
    function updateEventTemplate(
        address newTemplate
    ) external override onlyOwner {
        if (newTemplate == address(0)) revert CustomErrors.ZeroAddress();
        binaryOptionImplementation = newTemplate;
    }

    /**
     * @dev 移除过期的事件
     */
    function removeExpiredEvents() external {
        uint256 removedCount = 0;

        for (uint256 i = 0; i < activeEvents.length; i++) {
            if (activeEvents[i] != address(0)) {
                try IPredictionEvent(activeEvents[i]).getEventInfo() returns (
                    IPredictionEvent.Event memory eventInfo
                ) {
                    if (block.timestamp > eventInfo.endTime) {
                        isEventActive[activeEvents[i]] = false;
                        activeEvents[i] = address(0); // 清空地址
                        removedCount++;
                    }
                } catch {
                    // 如果事件合约出现问题，也移除
                    isEventActive[activeEvents[i]] = false;
                    activeEvents[i] = address(0);
                    removedCount++;
                }
            }
        }

        // 压缩数组
        _compressActiveEvents();
        totalActiveEvents -= removedCount;
    }

    /**
     * @dev 记录新事件
     */
    function _recordEvent(
        address eventAddress,
        string memory tokenSymbol
    ) internal {
        activeEvents.push(eventAddress);
        eventsByToken[tokenSymbol].push(eventAddress);
        isEventActive[eventAddress] = true;
        eventIndex[eventAddress] = activeEvents.length - 1;

        totalActiveEvents++;
        totalEventsCreated++;
    }

    /**
     * @dev 压缩活跃事件数组
     */
    function _compressActiveEvents() internal {
        uint256 writeIndex = 0;

        for (uint256 i = 0; i < activeEvents.length; i++) {
            if (activeEvents[i] != address(0)) {
                activeEvents[writeIndex] = activeEvents[i];
                writeIndex++;
            }
        }

        // 截断数组
        assembly {
            mstore(activeEvents.slot, writeIndex)
        }
    }

    /**
     * @dev 设置风险管理者
     */
    function setRiskManager(address newRiskManager) external onlyOwner {
        riskManager = newRiskManager;
    }

    /**
     * @dev 设置限制参数
     */
    function setLimits(
        uint256 _maxEventsPerToken,
        uint256 _maxActiveEvents
    ) external onlyRiskManager {
        maxEventsPerToken = _maxEventsPerToken;
        maxActiveEvents = _maxActiveEvents;
    }

    /**
     * @dev 设置支持的代币
     */
    function setSupportedTokens(
        address[] memory newSupportedTokens
    ) external onlyOwner {
        supportedTokens = newSupportedTokens;
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
     * @dev 紧急暂停事件创建
     */
    function emergencyStop() external onlyOwner {
        eventCreationEnabled = false;
        _pause();
    }

    /**
     * @dev 获取统计信息
     */
    function getStatistics()
        external
        view
        returns (
            uint256 _totalEventsCreated,
            uint256 _totalActiveEvents,
            uint256 _maxActiveEvents,
            bool _eventCreationEnabled
        )
    {
        return (
            totalEventsCreated,
            totalActiveEvents,
            maxActiveEvents,
            eventCreationEnabled
        );
    }

    /**
     * @dev 检查事件参数是否有效
     */
    function validateEventParameters(
        EventParams calldata params
    ) external view returns (bool) {
        if (bytes(params.tokenSymbol).length == 0) return false;
        if (params.priceFeed == address(0)) return false;
        if (params.duration < 5 minutes || params.duration > 24 hours)
            return false;
        if (params.strikePrice == 0 || params.targetPrice == 0) return false;
        if (!IPriceOracle(priceOracle).isTokenSupported(params.priceFeed))
            return false;
        if (eventsByToken[params.tokenSymbol].length >= maxEventsPerToken)
            return false;
        if (totalActiveEvents >= maxActiveEvents) return false;

        return true;
    }
}
