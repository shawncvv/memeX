// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {MemePredictionMarket} from "../src/MemePredictionMarket.sol";

/// @dev Deploy script for MemePredictionMarket
contract DeployMemePredictionMarket is Script {
    function run() public {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        if (deployerPrivateKey == 0) {
            console2.log("Warning: PRIVATE_KEY not set, using default test key");
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        }

        // Fee recipient address
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        if (feeRecipient == address(0)) {
            feeRecipient = vm.addr(deployerPrivateKey);
            console2.log("Using deployer as fee recipient");
        }

        // Supported tokens - load from env or use defaults
        address usdc = vm.envAddress("USDC_ADDRESS");
        address usdt = vm.envAddress("USDT_ADDRESS");

        // Default to zero addresses if not set (will need to be added later)
        if (usdc == address(0)) {
            console2.log("Warning: USDC_ADDRESS not set, using address(0)");
        }
        if (usdt == address(0)) {
            console2.log("Warning: USDT_ADDRESS not set, will add later via addSupportedToken()");
        }

        // Count how many tokens to support
        uint256 tokenCount = 0;
        if (usdc != address(0)) tokenCount++;
        if (usdt != address(0)) tokenCount++;

        address[] memory supportedTokens = new address[](tokenCount);
        uint256 idx = 0;
        if (usdc != address(0)) {
            supportedTokens[idx] = usdc;
            console2.log("USDC:", usdc);
            idx++;
        }
        if (usdt != address(0)) {
            supportedTokens[idx] = usdt;
            console2.log("USDT:", usdt);
        }

        console2.log("Deploying MemePredictionMarket...");
        console2.log("Fee recipient:", feeRecipient);

        vm.startBroadcast(deployerPrivateKey);

        MemePredictionMarket market = new MemePredictionMarket(feeRecipient, supportedTokens);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Deployment Summary ===");
        console2.log("Contract Address:", address(market));
        console2.log("Owner:", market.owner());
        console2.log("Fee Recipient:", market.feeRecipient());
        console2.log("");

        // Output for verification
        console2.log("Add to .env file:");
        console2.log("MARKET_ADDRESS=", address(market));
    }
}
