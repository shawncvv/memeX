// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Events} from "./libraries/Events.sol";
import {Errors} from "./libraries/Errors.sol";

/**
 * @title AccessController
 * @dev 访问控制合约，管理所有合约的权限
 */
contract AccessController is AccessControl, Ownable {
    // 角色定义
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // 管理的合约地址
    mapping(string => address) public contractAddresses;
    string[] public contractNames;

    // 多签钱包支持
    address public multiSigWallet;
    uint256 public constant REQUIRED_SIGNATURES = 2;
    mapping(bytes32 => mapping(address => bool)) public signatures;

    // 时间锁
    uint256 public constant TIME_LOCK_DELAY = 48 hours;
    mapping(bytes32 => uint256) public timeLocks;

    // Internal check functions
    function _checkMultiSig() private view {
        require(
            msg.sender == multiSigWallet || hasRole(ADMIN_ROLE, msg.sender),
            "Unauthorized"
        );
    }

    function _checkTimelocked(bytes32 operationId) private {
        require(
            block.timestamp >= timeLocks[operationId],
            TimelockNotExpired()
        );
        delete timeLocks[operationId];
    }

    // Modifiers
    modifier onlyMultiSig() {
        _checkMultiSig();
        _;
    }

    modifier onlyTimelocked(bytes32 operationId) {
        _checkTimelocked(operationId);
        _;
    }

    constructor() Ownable(msg.sender) {
        // 初始化角色
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
        _grantRole(RISK_MANAGER_ROLE, msg.sender);
        _grantRole(TREASURY_ROLE, msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
    }

    /**
     * @dev 设置多签钱包
     */
    function setMultiSigWallet(
        address _multiSigWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_multiSigWallet == address(0)) revert Errors.ZeroAddress();
        multiSigWallet = _multiSigWallet;
    }

    /**
     * @dev 添加合约地址
     */
    function addContract(
        string calldata name,
        address contractAddress
    ) external onlyRole(ADMIN_ROLE) {
        if (contractAddress == address(0)) revert Errors.ZeroAddress();
        if (bytes(name).length == 0) revert Errors.EmptyString();

        // 如果合约已存在，更新地址
        if (contractAddresses[name] == address(0)) {
            contractNames.push(name);
        }

        contractAddresses[name] = contractAddress;
    }

    /**
     * @dev 移除合约地址
     */
    function removeContract(
        string calldata name
    ) external onlyRole(ADMIN_ROLE) {
        if (contractAddresses[name] == address(0))
            revert Errors.InvalidAddress();

        // 从数组中移除
        for (uint256 i = 0; i < contractNames.length; i++) {
            if (keccak256(bytes(contractNames[i])) == keccak256(bytes(name))) {
                contractNames[i] = contractNames[contractNames.length - 1];
                contractNames.pop();
                break;
            }
        }

        delete contractAddresses[name];
    }

    /**
     * @dev 获取合约地址
     */
    function getContract(string calldata name) external view returns (address) {
        return contractAddresses[name];
    }

    /**
     * @dev 获取所有合约地址
     */
    function getAllContracts()
        external
        view
        returns (string[] memory names, address[] memory addresses)
    {
        uint256 length = contractNames.length;
        names = new string[](length);
        addresses = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            names[i] = contractNames[i];
            addresses[i] = contractAddresses[contractNames[i]];
        }
    }

    /**
     * @dev 检查地址是否有特定权限
     */
    function hasPermission(
        address account,
        string calldata permission
    ) external view returns (bool) {
        bytes32 role;

        if (keccak256(bytes(permission)) == keccak256(bytes("admin"))) {
            role = ADMIN_ROLE;
        } else if (
            keccak256(bytes(permission)) == keccak256(bytes("operator"))
        ) {
            role = OPERATOR_ROLE;
        } else if (keccak256(bytes(permission)) == keccak256(bytes("oracle"))) {
            role = ORACLE_ROLE;
        } else if (
            keccak256(bytes(permission)) == keccak256(bytes("risk_manager"))
        ) {
            role = RISK_MANAGER_ROLE;
        } else if (
            keccak256(bytes(permission)) == keccak256(bytes("treasury"))
        ) {
            role = TREASURY_ROLE;
        } else if (
            keccak256(bytes(permission)) == keccak256(bytes("emergency"))
        ) {
            role = EMERGENCY_ROLE;
        } else {
            return false;
        }

        return hasRole(role, account);
    }

    /**
     * @dev 时间锁操作 - 调用合约函数
     */
    function timelockedCall(
        address target,
        bytes calldata data,
        uint256 value
    ) external onlyMultiSig returns (bytes32 operationId) {
        operationId = keccak256(
            abi.encodePacked(target, data, value, block.timestamp, msg.sender)
        );

        timeLocks[operationId] = block.timestamp + TIME_LOCK_DELAY;
        emit TimelockScheduled(
            operationId,
            target,
            data,
            value,
            block.timestamp + TIME_LOCK_DELAY
        );
    }

    /**
     * @dev 执行时间锁操作
     */
    function executeTimelockedCall(
        address target,
        bytes calldata data,
        uint256 value,
        bytes32 operationId
    ) external onlyMultiSig onlyTimelocked(operationId) returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) revert ExecutionFailed();

        emit TimelockExecuted(operationId, target, success);
        return result;
    }

    /**
     * @dev 批量设置角色
     */
    function batchGrantRoles(
        address[] calldata accounts,
        bytes32[] calldata roles
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (accounts.length != roles.length)
            revert Errors.ArrayLengthMismatch();

        for (uint256 i = 0; i < accounts.length; i++) {
            _grantRole(roles[i], accounts[i]);
            emit Events.RoleGranted(
                roles[i],
                accounts[i],
                msg.sender,
                block.timestamp
            );
        }
    }

    /**
     * @dev 批量撤销角色
     */
    function batchRevokeRoles(
        address[] calldata accounts,
        bytes32[] calldata roles
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(accounts.length == roles.length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < accounts.length; i++) {
            _revokeRole(roles[i], accounts[i]);
            emit Events.RoleRevoked(
                roles[i],
                accounts[i],
                msg.sender,
                block.timestamp
            );
        }
    }

    /**
     * @dev 检查操作是否需要多签
     */
    function requiresMultiSig(
        string calldata operation
    ) external pure returns (bool) {
        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 opHash = keccak256(bytes(operation));

        // 需要多签的操作
        return
            opHash == keccak256(bytes("upgrade_contract")) ||
            opHash == keccak256(bytes("change_admin")) ||
            opHash == keccak256(bytes("emergency_pause")) ||
            opHash == keccak256(bytes("withdraw_funds"));
    }

    /**
     * @dev 紧急暂停所有合约
     */
    function emergencyPauseAll() external onlyRole(EMERGENCY_ROLE) {
        string[] memory names = contractNames;

        for (uint256 i = 0; i < names.length; i++) {
            address contractAddr = contractAddresses[names[i]];
            if (contractAddr != address(0)) {
                (bool success, ) = contractAddr.call(
                    abi.encodeWithSignature("pause()")
                );
                if (success) {
                    emit EmergencyPauseTriggered(names[i], block.timestamp);
                }
                // 忽略错误，继续处理其他合约
            }
        }
    }

    /**
     * @dev 紧急恢复所有合约
     */
    function emergencyUnpauseAll() external onlyRole(EMERGENCY_ROLE) {
        string[] memory names = contractNames;

        for (uint256 i = 0; i < names.length; i++) {
            address contractAddr = contractAddresses[names[i]];
            if (contractAddr != address(0)) {
                (bool success, ) = contractAddr.call(
                    abi.encodeWithSignature("unpause()")
                );
                if (success) {
                    emit EmergencyUnpauseTriggered(names[i], block.timestamp);
                }
                // 忽略错误，继续处理其他合约
            }
        }
    }

    /**
     * @dev 检查账户是否为操作员
     */
    function isOperator(address account) external view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev 检查账户是否为预言机
     */
    function isOracle(address account) external view returns (bool) {
        return hasRole(ORACLE_ROLE, account);
    }

    /**
     * @dev 检查账户是否为风险管理者
     */
    function isRiskManager(address account) external view returns (bool) {
        return hasRole(RISK_MANAGER_ROLE, account);
    }

    /**
     * @dev 检查账户是否为财库管理者
     */
    function isTreasury(address account) external view returns (bool) {
        return hasRole(TREASURY_ROLE, account);
    }

    /**
     * @dev 获取用户的所有角色
     */
    function getUserRoles(
        address account
    ) external view returns (bytes32[] memory) {
        bytes32[] memory allRoles = new bytes32[](6);
        uint256 count = 0;

        if (hasRole(DEFAULT_ADMIN_ROLE, account)) {
            allRoles[count] = DEFAULT_ADMIN_ROLE;
            count++;
        }
        if (hasRole(ADMIN_ROLE, account)) {
            allRoles[count] = ADMIN_ROLE;
            count++;
        }
        if (hasRole(OPERATOR_ROLE, account)) {
            allRoles[count] = OPERATOR_ROLE;
            count++;
        }
        if (hasRole(ORACLE_ROLE, account)) {
            allRoles[count] = ORACLE_ROLE;
            count++;
        }
        if (hasRole(RISK_MANAGER_ROLE, account)) {
            allRoles[count] = RISK_MANAGER_ROLE;
            count++;
        }
        if (hasRole(TREASURY_ROLE, account)) {
            allRoles[count] = TREASURY_ROLE;
            count++;
        }

        // 调整数组大小
        bytes32[] memory result = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = allRoles[i];
        }

        return result;
    }

    /**
     * @dev 获取时间锁信息
     */
    function getTimelock(bytes32 operationId) external view returns (uint256) {
        return timeLocks[operationId];
    }

    // 事件定义
    event TimelockScheduled(
        bytes32 indexed operationId,
        address indexed target,
        bytes data,
        uint256 value,
        uint256 executeTime
    );

    event TimelockExecuted(
        bytes32 indexed operationId,
        address indexed target,
        bool success
    );

    event EmergencyPauseTriggered(
        string indexed contractName,
        uint256 timestamp
    );

    event EmergencyUnpauseTriggered(
        string indexed contractName,
        uint256 timestamp
    );

    // 错误定义
    error TimelockNotExpired();
    error ExecutionFailed();
}
