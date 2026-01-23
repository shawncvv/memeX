// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {MemePredictionMarket} from "../src/MemePredictionMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Simple ERC20 for testing
contract TestToken is IERC20 {
    string public constant name = "TestToken";
    string public constant symbol = "TEST";
    uint8 public constant decimals = 18;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    constructor() {}

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }

    // Mint tokens for testing
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }
}

contract MemePredictionMarketTest is Test {
    MemePredictionMarket public market;
    TestToken public usdc;

    address public owner;
    address public feeRecipient;
    address public user1;
    address public user2;

    function setUp() public {
        owner = makeAddr("owner");
        feeRecipient = makeAddr("feeRecipient");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy test token (USDC mock)
        usdc = new TestToken();

        // Give users tokens
        usdc.mint(user1, 1000 ether);
        usdc.mint(user2, 1000 ether);

        // Deploy market
        vm.prank(owner);
        market = new MemePredictionMarket(feeRecipient);
    }

    // ============ 创建事件测试 ============
    function testCreateEvent() public {
        vm.prank(owner);
        uint256 eventId = market.createEvent("PEPE", 1000000, 3600);

        assertEq(eventId, 1);

        MemePredictionMarket.Event memory evt = market.getEvent(eventId);
        assertEq(evt.tokenSymbol, "PEPE");
        assertEq(evt.basePrice, 1000000);
        assertEq(evt.endTime, block.timestamp + 3600);
        assertEq(uint(evt.status), 0);
    }

    function testCreateEventInvalidDuration() public {
        vm.prank(owner);
        vm.expectRevert("Invalid duration");
        market.createEvent("PEPE", 1000000, 100);
    }

    // ============ 下注测试 ============
    function testPlaceBet() public {
        vm.prank(owner);
        uint256 eventId = market.createEvent("PEPE", 1000000, 3600);

        vm.prank(user1);
        usdc.approve(address(market), 1 ether);
        market.placeBet(eventId, true, 1 ether);

        MemePredictionMarket.Event memory evt = market.getEvent(eventId);
        assertEq(evt.yesPool, 1 ether);
        assertEq(evt.totalPool, 1 ether);
    }

    function testPlaceBetMultipleUsers() public {
        vm.prank(owner);
        uint256 eventId = market.createEvent("PEPE", 1000000, 3600);

        vm.prank(user1);
        usdc.approve(address(market), 1 ether);
        market.placeBet(eventId, true, 1 ether);

        vm.prank(user2);
        usdc.approve(address(market), 3 ether);
        market.placeBet(eventId, false, 3 ether);

        MemePredictionMarket.Event memory evt = market.getEvent(eventId);
        assertEq(evt.yesPool, 1 ether);
        assertEq(evt.noPool, 3 ether);
        assertEq(evt.totalPool, 4 ether);
    }

    // ============ 赔率测试 ============
    function testGetCurrentOdds() public {
        vm.prank(owner);
        uint256 eventId = market.createEvent("PEPE", 1000000, 3600);

        vm.prank(user1);
        usdc.approve(address(market), 1 ether);
        market.placeBet(eventId, true, 1 ether);

        vm.prank(user2);
        usdc.approve(address(market), 1 ether);
        market.placeBet(eventId, false, 1 ether);

        (uint256 yesOdds, uint256 noOdds) = market.getCurrentOdds(eventId);
        assertEq(yesOdds, 5e17);
        assertEq(noOdds, 5e17);
    }

    // ============ 结算测试 ============
    function testResolveEventYesWins() public {
        vm.prank(owner);
        uint256 eventId = market.createEvent("PEPE", 1000000, 3600);

        vm.prank(user1);
        usdc.approve(address(market), 1 ether);
        market.placeBet(eventId, true, 1 ether);

        vm.prank(user2);
        usdc.approve(address(market), 1 ether);
        market.placeBet(eventId, false, 1 ether);

        vm.warp(block.timestamp + 3601);

        vm.prank(owner);
        market.resolveEvent(eventId, 1100000);

        MemePredictionMarket.Event memory evt = market.getEvent(eventId);
        assertTrue(evt.yesWins);
    }

    function testResolveEventNoWins() public {
        vm.prank(owner);
        uint256 eventId = market.createEvent("PEPE", 1000000, 3600);

        vm.prank(user1);
        usdc.approve(address(market), 1 ether);
        market.placeBet(eventId, true, 1 ether);

        vm.prank(user2);
        usdc.approve(address(market), 1 ether);
        market.placeBet(eventId, false, 1 ether);

        vm.warp(block.timestamp + 3601);

        vm.prank(owner);
        market.resolveEvent(eventId, 900000);

        MemePredictionMarket.Event memory evt = market.getEvent(eventId);
        assertFalse(evt.yesWins);
    }

    // ============ 领取奖励测试 ============
    function testClaimRewardsYesWins() public {
        vm.prank(owner);
        uint256 eventId = market.createEvent("PEPE", 1000000, 3600);

        vm.prank(user1);
        usdc.approve(address(market), 1 ether);
        market.placeBet(eventId, true, 1 ether);

        vm.prank(user2);
        usdc.approve(address(market), 1 ether);
        market.placeBet(eventId, false, 1 ether);

        vm.warp(block.timestamp + 3601);

        vm.prank(owner);
        market.resolveEvent(eventId, 1100000);

        uint256 user1BalanceBefore = usdc.balanceOf(user1);
        vm.prank(user1);
        market.claimRewards(eventId);
        uint256 user1BalanceAfter = usdc.balanceOf(user1);

        assertGt(user1BalanceAfter, user1BalanceBefore);
    }

    function testClaimRewardsNoWins() public {
        vm.prank(owner);
        uint256 eventId = market.createEvent("PEPE", 1000000, 3600);

        vm.prank(user1);
        usdc.approve(address(market), 1 ether);
        market.placeBet(eventId, true, 1 ether);

        vm.prank(user2);
        usdc.approve(address(market), 1 ether);
        market.placeBet(eventId, false, 1 ether);

        vm.warp(block.timestamp + 3601);

        vm.prank(owner);
        market.resolveEvent(eventId, 900000);

        vm.prank(user1);
        vm.expectRevert("You lost");
        market.claimRewards(eventId);
    }

    // ============ 完整流程测试 ============
    function testFullFlow() public {
        vm.prank(owner);
        uint256 eventId = market.createEvent("PEPE", 1000000, 3600);

        vm.prank(user1);
        usdc.approve(address(market), 10 ether);
        market.placeBet(eventId, true, 10 ether);

        vm.prank(user2);
        usdc.approve(address(market), 10 ether);
        market.placeBet(eventId, false, 10 ether);

        (uint256 yesOdds, ) = market.getCurrentOdds(eventId);
        assertEq(yesOdds, 5e17);

        vm.warp(block.timestamp + 3601);

        vm.prank(owner);
        market.resolveEvent(eventId, 1200000);

        uint256 user1BalanceBefore = usdc.balanceOf(user1);
        vm.prank(user1);
        market.claimRewards(eventId);
        uint256 user1BalanceAfter = usdc.balanceOf(user1);

        assertGt(user1BalanceAfter, user1BalanceBefore);
    }

    // ============ CPMM 数学测试 ============
    function testCPMMOddsCalculation() public {
        vm.prank(owner);
        uint256 eventId = market.createEvent("PEPE", 1000000, 3600);

        vm.prank(user1);
        usdc.approve(address(market), 100 ether);
        market.placeBet(eventId, true, 100 ether);

        vm.prank(user2);
        usdc.approve(address(market), 300 ether);
        market.placeBet(eventId, false, 300 ether);

        (uint256 yesOdds, uint256 noOdds) = market.getCurrentOdds(eventId);
        assertEq(yesOdds, 25e16);
        assertEq(noOdds, 75e16);
    }
}
