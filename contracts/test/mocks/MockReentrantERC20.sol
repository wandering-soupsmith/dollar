// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IReentryTarget {
    function withdraw(uint16 poolId, address asset, uint256 units, uint256 deadline) external returns (uint256);
}

/// @notice Malicious ERC20 that reenters the DollarStore on an outbound payout transfer.
/// @dev Used to prove the nonReentrant guard blocks reentrancy on token-moving paths. The reentry
///      fires only when the token is moving FROM the store TO a user (a payout), and only once,
///      so it trips the guard cleanly rather than looping.
contract MockReentrantERC20 is ERC20 {
    uint8 private immutable _decimals;
    address public store;
    bool public attack;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Arm the reentrancy: the next payout (store -> user) reenters store.withdraw.
    function arm(address store_) external {
        store = store_;
        attack = true;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (attack && store != address(0) && from == store && to != store) {
            attack = false; // one shot; the reentrant call reverts on the guard
            IReentryTarget(store).withdraw(0, address(this), 1, block.timestamp);
        }
    }
}
