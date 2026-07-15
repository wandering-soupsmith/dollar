// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RegistryStorage} from "../src/storage/RegistryStorage.sol";

/// @notice Harness exercising RegistryStorage against the harness's own storage.
contract RegistryStorageHarness {
    function pushPool(RegistryStorage.PoolKind kind) external returns (uint256 id) {
        RegistryStorage.Pool storage p = RegistryStorage.layout().pools.push();
        p.kind = kind;
        return RegistryStorage.layout().pools.length - 1;
    }

    function poolCount() external view returns (uint256) {
        return RegistryStorage.layout().pools.length;
    }

    function poolKind(uint256 id) external view returns (RegistryStorage.PoolKind) {
        return RegistryStorage.layout().pools[id].kind;
    }

    function addAssetToPool(uint16 poolId, address asset) external {
        RegistryStorage.layout().pools[poolId].assets.push(asset);
    }

    function poolAssets(uint16 poolId) external view returns (address[] memory) {
        return RegistryStorage.layout().pools[poolId].assets;
    }

    function setConfig(address asset, uint16 poolId, uint8 dec, uint64 sf) external {
        RegistryStorage.layout().assetConfig[asset] = RegistryStorage.AssetConfig({
            poolId: poolId,
            decimals: dec,
            scalingFactor: sf,
            priceFeed: address(0xFEED),
            listed: true,
            depositPaused: false
        });
    }

    function isListed(address asset) external view returns (bool) {
        return RegistryStorage.layout().assetConfig[asset].listed;
    }

    function setReserve(uint16 poolId, address asset, uint256 amount) external {
        RegistryStorage.layout().reserves[poolId][asset] = amount;
    }

    function getReserve(uint16 poolId, address asset) external view returns (uint256) {
        return RegistryStorage.layout().reserves[poolId][asset];
    }
}

contract RegistryStorageTest is Test {
    RegistryStorageHarness internal h;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        h = new RegistryStorageHarness();
    }

    /// @notice Guards the hardcoded slot against transcription errors.
    function test_storageSlot_matchesFormula() public {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("dollarstore.storage.registry")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(RegistryStorage.REGISTRY_STORAGE_LOCATION, expected, "registry slot mismatch");
    }

    function test_pools_roundTrip() public {
        assertEq(h.poolCount(), 0, "starts empty");
        uint256 hubId = h.pushPool(RegistryStorage.PoolKind.Hub);
        uint256 spokeId = h.pushPool(RegistryStorage.PoolKind.Spoke);
        assertEq(hubId, 0, "hub id");
        assertEq(spokeId, 1, "spoke id");
        assertEq(h.poolCount(), 2, "two pools");
        assertTrue(h.poolKind(0) == RegistryStorage.PoolKind.Hub, "hub kind");
        assertTrue(h.poolKind(1) == RegistryStorage.PoolKind.Spoke, "spoke kind");
    }

    function test_assets_and_config_roundTrip() public {
        h.pushPool(RegistryStorage.PoolKind.Hub);
        h.setConfig(USDC, 0, 6, 1);
        assertTrue(h.isListed(USDC), "listed");

        h.addAssetToPool(0, USDC);
        address[] memory a = h.poolAssets(0);
        assertEq(a.length, 1, "one asset");
        assertEq(a[0], USDC, "asset addr");
    }

    function test_reserves_roundTrip() public {
        assertEq(h.getReserve(0, USDC), 0, "starts zero");
        h.setReserve(0, USDC, 1_000e6);
        assertEq(h.getReserve(0, USDC), 1_000e6, "reserve set");
        // Different pool id is isolated.
        assertEq(h.getReserve(1, USDC), 0, "other pool isolated");
    }
}
