// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";

/// @title TestnetPriceFeed - configurable, always-fresh price feed for Sepolia rehearsals.
/// @notice Reports a settable answer (default $1 at 8 decimals) with updatedAt == block.timestamp,
///         so it never trips the staleness check. Call setAnswer to simulate a depeg.
///         TESTNET/REHEARSAL ONLY - never use in production.
contract TestnetPriceFeed is AggregatorV3Interface {
    uint8 public immutable feedDecimals;
    int256 public answer;

    constructor(uint8 decimals_, int256 initialAnswer) {
        feedDecimals = decimals_;
        answer = initialAnswer;
    }

    /// @notice Set the reported price (feed decimals). e.g. 99_000_000 (8dp) = $0.99 to force a depeg.
    function setAnswer(int256 newAnswer) external {
        answer = newAnswer;
    }

    function decimals() external view override returns (uint8) {
        return feedDecimals;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer_, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, answer, block.timestamp, block.timestamp, 1);
    }
}
