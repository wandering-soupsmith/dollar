// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice ERC20 that charges a fee on transfers (NOT on mint/burn), so the recipient receives
///         less than `value`. Used to verify the protocol rejects fee-on-transfer tokens.
contract MockFeeOnTransferERC20 is ERC20 {
    uint8 private immutable _dec;
    uint256 public immutable feeBps;
    address public constant SINK = address(0xFEE5);

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 feeBps_) ERC20(name_, symbol_) {
        _dec = decimals_;
        feeBps = feeBps_;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        // Apply the fee only on real transfers (skip mint: from==0, and burn: to==0).
        if (from != address(0) && to != address(0) && feeBps > 0) {
            uint256 fee = (value * feeBps) / 10_000;
            super._update(from, to, value - fee);
            if (fee > 0) super._update(from, SINK, fee);
        } else {
            super._update(from, to, value);
        }
    }
}
