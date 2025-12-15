// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPredictionEvent} from "./IPredictionEvent.sol";

interface IAIOracle {
    struct AiPrediction {
        bytes32 requestId;
        bytes32 eventId;
        address user;
        string question;
        IPredictionEvent.Position recommendation;
        uint256 confidence; // 0-100%
        string reasoning; // AI推理过程
        uint256 timestamp;
        bool paid;
        bool completed;
    }

    event PredictionRequested(
        bytes32 indexed requestId,
        address indexed user,
        bytes32 indexed eventId,
        string question
    );

    event PredictionCompleted(
        bytes32 indexed requestId,
        IPredictionEvent.Position recommendation,
        uint256 confidence,
        string reasoning
    );

    event PaymentForAI(
        address indexed user,
        bytes32 indexed requestId,
        uint256 amount
    );

    function requestPrediction(
        bytes32 eventId,
        string calldata question
    ) external payable returns (bytes32 requestId);

    function getPrediction(
        bytes32 requestId
    ) external view returns (AiPrediction memory);

    function getLatestPrediction(
        address user,
        bytes32 eventId
    ) external view returns (AiPrediction memory);

    function hasPaidForPrediction(
        address user,
        bytes32 eventId
    ) external view returns (bool);

    function setPredictionPrice(uint256 newPrice) external;

    function updateAiService(address newService) external;

    function withdrawFees() external;
}
