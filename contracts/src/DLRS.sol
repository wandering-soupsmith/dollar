// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title DLRS - Dollar Store Token
/// @notice ERC-20 receipt token representing a 1:1 claim on the Dollar Store reserve pool
/// @dev Only the DollarStore contract can mint and burn tokens
contract DLRS is ERC20 {
    address public immutable dollarStore;

    error OnlyDollarStore();

    modifier onlyDollarStore() {
        if (msg.sender != dollarStore) revert OnlyDollarStore();
        _;
    }

    constructor(address _dollarStore) ERC20("Dollar Store Token", "DLRS") {
        dollarStore = _dollarStore;
    }

    /// @notice Mint DLRS tokens to a recipient
    /// @param to The address to receive the tokens
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external onlyDollarStore {
        _mint(to, amount);
    }

    /// @notice Burn DLRS tokens from an account
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    function burn(address from, uint256 amount) external onlyDollarStore {
        _burn(from, amount);
    }
}
