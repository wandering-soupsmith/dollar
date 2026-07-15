// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AggregatorV3Interface - Minimal Chainlink price feed interface used by the peg check.
interface AggregatorV3Interface {
    /// @notice Number of decimals in the feed's answer.
    function decimals() external view returns (uint8);

    /// @notice Latest round data.
    /// @return roundId The round id.
    /// @return answer The price answer (feed decimals).
    /// @return startedAt When the round started.
    /// @return updatedAt When the answer was last updated.
    /// @return answeredInRound The round in which the answer was computed.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
