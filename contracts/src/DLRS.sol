// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title DLRS - Dollar Store Token
/// @notice ERC-20 receipt token representing a 1:1 claim on the Dollar Store reserve pool.
/// @dev Non-transferable / soulbound by design (transfer, approve, transferFrom revert).
/// @dev NOT upgradeable: this token is immutable and bound to the DollarStore proxy.
/// @dev Only the DollarStore contract (the proxy address) can mint and burn tokens.
/// @dev Uses 6 decimals to match underlying stablecoins (USDC, USDT).
/// @custom:security-contact admin@dollarstore.world
contract DLRS is ERC20 {
    /// @notice Address of the DollarStore contract (proxy) authorized to mint and burn.
    address public immutable dollarStore;

    error OnlyDollarStore();
    error ZeroAddress();
    error NonTransferable();

    modifier onlyDollarStore() {
        if (msg.sender != dollarStore) revert OnlyDollarStore();
        _;
    }

    /// @param _dollarStore The DollarStore proxy address authorized to mint/burn.
    constructor(address _dollarStore) ERC20("Dollar Store Token", "DLRS") {
        if (_dollarStore == address(0)) revert ZeroAddress();
        dollarStore = _dollarStore;
    }

    /// @notice Returns 6 decimals to match underlying stablecoins.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mint DLRS tokens to a recipient.
    /// @param to The address to receive the tokens.
    /// @param amount The amount of tokens to mint.
    function mint(address to, uint256 amount) external onlyDollarStore {
        _mint(to, amount);
    }

    /// @notice Burn DLRS tokens from an account.
    /// @param from The address to burn tokens from.
    /// @param amount The amount of tokens to burn.
    function burn(address from, uint256 amount) external onlyDollarStore {
        _burn(from, amount);
    }

    /// @notice DLRS is non-transferable — approvals are blocked.
    function approve(address, uint256) public pure override returns (bool) {
        revert NonTransferable();
    }

    /// @notice DLRS is non-transferable (soulbound).
    function transfer(address, uint256) public pure override returns (bool) {
        revert NonTransferable();
    }

    /// @notice DLRS is non-transferable (soulbound).
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert NonTransferable();
    }
}
