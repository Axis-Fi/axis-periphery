// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Test scaffolding
import {BaselineAxisLaunchTest} from "../BaselineAxisLaunchTest.sol";

// Axis
import {BALwithAllocatedAllowlist} from
    "../../../../../src/callbacks/liquidity/BaselineV2/BALwithAllocatedAllowlist.sol";

contract BaselineAllocatedAllowlistTest is BaselineAxisLaunchTest {
    // ========== MODIFIERS ========== //

    modifier givenCallbackIsCreated() override {
        // Get the salt
        bytes memory args =
            abi.encode(address(_auctionHouse), _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN, _OWNER);
        bytes32 salt = _getTestSalt(
            "BaselineAllocatedAllowlist", type(BALwithAllocatedAllowlist).creationCode, args
        );

        // Required for CREATE2 address to work correctly. doesn't do anything in a test
        // Source: https://github.com/foundry-rs/foundry/issues/6402
        vm.startBroadcast();
        _dtl = new BALwithAllocatedAllowlist{salt: salt}(
            address(_auctionHouse), _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN, _OWNER
        );
        vm.stopBroadcast();

        _dtlAddress = address(_dtl);

        // Call configureDependencies to set everything that's needed
        _mockBaselineGetModuleForKeycode();
        _dtl.configureDependencies();
        _;
    }

    modifier givenAllowlistParams(bytes32 merkleRoot_) {
        _createData.allowlistParams = abi.encode(merkleRoot_);
        _;
    }
}
