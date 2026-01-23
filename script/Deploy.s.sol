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

        console2.log("Deploying MemePredictionMarket...");
        console2.log("Fee recipient:", feeRecipient);

        vm.startBroadcast(deployerPrivateKey);

        MemePredictionMarket market = new MemePredictionMarket(feeRecipient);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Deployment Summary ===");
        console2.log("Contract Address:", address(market));
        console2.log("Owner:", market.owner());
        console2.log("Fee Recipient:", market.feeRecipient());
        console2.log("USDC:", market.USDC());
        console2.log("");

        // Output for verification
        console2.log("Add to .env file:");
        console2.log("MARKET_ADDRESS=", address(market));
    }
}
