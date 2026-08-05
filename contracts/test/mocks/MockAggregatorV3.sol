// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";

/// @notice Configurable mock Chainlink feed for tests. Defaults to a fresh $1 price.
contract MockAggregatorV3 is AggregatorV3Interface {
    uint8 public override decimals;
    int256 public answer;
    uint256 public updatedAt;
    uint80 public roundId;
    uint80 public answeredInRound;
    bool public reverts; // when true, latestRoundData reverts (simulates a broken feed)

    constructor(uint8 _decimals, int256 _answer) {
        decimals = _decimals;
        answer = _answer;
        updatedAt = block.timestamp;
        roundId = 1;
        answeredInRound = 1;
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        if (reverts) revert("feed down");
        return (roundId, answer, updatedAt, updatedAt, answeredInRound);
    }

    // ---- test setters ----
    function setReverts(bool r) external {
        reverts = r;
    }

    function setAnswer(int256 a) external {
        answer = a;
    }

    function setUpdatedAt(uint256 t) external {
        updatedAt = t;
    }

    function setRound(uint80 r, uint80 ar) external {
        roundId = r;
        answeredInRound = ar;
    }
}
