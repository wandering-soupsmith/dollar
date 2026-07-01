// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice ERC20 with a settable blacklist: transfers TO a blocked address revert. Used to
///         exercise the protocol's failed-transfer fallbacks (escrow -> DLRS claim), which keep
///         the DLRS.totalSupply == sum(reserves) invariant intact when a recipient is frozen.
/// @dev Mirrors real-world stablecoins (USDC/USDT) whose transfers revert on blocked recipients.
contract MockBlacklistERC20 is ERC20 {
    uint8 private immutable _decimals;

    mapping(address => bool) public blocked;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Toggle whether transfers to `account` revert. Set AFTER minting to `account`.
    function setBlocked(address account, bool value) external {
        blocked[account] = value;
    }

    function _update(address from, address to, uint256 value) internal override {
        require(!blocked[to], "blocked");
        super._update(from, to, value);
    }
}
