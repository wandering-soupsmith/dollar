// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockStableERC20 - Faucet-style ERC20 for testnet only
/// @notice Mock stablecoin used to simulate USDC / USDT on Sepolia. Anyone can mint.
/// @dev NOT for production. Deliberately isolated under contracts/testnet-mocks/ so it never
///      ships with the real protocol source in src/. Decimals are configurable at construction
///      to match the underlying asset it simulates (USDC and USDT both use 6 decimals).
contract MockStableERC20 is ERC20 {
    uint8 private immutable _decimals;

    /// @param name_     Token name (e.g. "USD Coin (Mock)").
    /// @param symbol_   Token symbol (e.g. "USDC").
    /// @param decimals_ Decimals to expose (6 for USDC/USDT).
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    /// @notice Returns the configured decimals (matches the simulated real asset).
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Public faucet mint - anyone can mint any amount to any address.
    /// @param to     Recipient of the freshly minted tokens.
    /// @param amount Amount in base units (remember: 6 decimals).
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Convenience faucet: mint to the caller.
    /// @param amount Amount in base units (6 decimals).
    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    /// @notice Burn tokens from the caller (useful for resetting balances in tests).
    /// @param amount Amount in base units (6 decimals).
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
