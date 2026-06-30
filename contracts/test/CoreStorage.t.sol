// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CoreStorage} from "../src/storage/CoreStorage.sol";

/// @notice Harness exercising CoreStorage against the harness's own storage.
contract CoreStorageHarness {
    function setGovernor(address a) external {
        CoreStorage.layout().governor = a;
    }

    function getGovernor() external view returns (address) {
        return CoreStorage.layout().governor;
    }

    function setDlrs(address a) external {
        CoreStorage.layout().dlrs = a;
    }

    function getDlrs() external view returns (address) {
        return CoreStorage.layout().dlrs;
    }
}

contract CoreStorageTest is Test {
    CoreStorageHarness internal h;

    function setUp() public {
        h = new CoreStorageHarness();
    }

    /// @notice Guards the hardcoded slot against transcription errors: it MUST equal the
    ///         ERC-7201 formula for namespace "dollarstore.storage.core".
    function test_storageSlot_matchesFormula() public {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("dollarstore.storage.core")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(CoreStorage.CORE_STORAGE_LOCATION, expected, "core slot mismatch");
    }

    /// @notice layout() round-trips through the namespaced slot.
    function test_layout_roundTrip() public {
        assertEq(h.getGovernor(), address(0), "starts zero");
        h.setGovernor(address(0xA11CE));
        h.setDlrs(address(0xBEEF));
        assertEq(h.getGovernor(), address(0xA11CE), "governor persisted");
        assertEq(h.getDlrs(), address(0xBEEF), "dlrs persisted");
    }
}
