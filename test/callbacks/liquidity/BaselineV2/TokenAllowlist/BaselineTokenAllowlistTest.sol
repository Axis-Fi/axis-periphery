// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Test scaffolding
import {BaselineAxisLaunchTest} from "../BaselineAxisLaunchTest.sol";
import {MockERC20} from "@solmate-6.8.0/test/utils/mocks/MockERC20.sol";

// Axis
import {
    BALwithTokenAllowlist,
    ITokenBalance
} from "../../../../../src/callbacks/liquidity/BaselineV2/BALwithTokenAllowlist.sol";

// Baseline
import {Actions as BaselineKernelActions} from "@baseline/Kernel.sol";

contract BaselineTokenAllowlistTest is BaselineAxisLaunchTest {
    uint96 internal constant _TOKEN_THRESHOLD = 5e18;
    MockERC20 internal _token;

    // ========== MODIFIERS ========== //

    modifier givenCallbackIsCreated() override {
        // Get the salt
        bytes memory args =
            abi.encode(address(_auctionHouse), _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN, _SELLER);
        bytes32 salt =
            _getTestSalt("BaselineTokenAllowlist", type(BALwithTokenAllowlist).creationCode, args);

        // Required for CREATE2 address to work correctly. doesn't do anything in a test
        // Source: https://github.com/foundry-rs/foundry/issues/6402
        vm.startBroadcast();
        _dtl = new BALwithTokenAllowlist{salt: salt}(
            address(_auctionHouse), _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN, _SELLER
        );
        vm.stopBroadcast();

        _dtlAddress = address(_dtl);

        // Install as a policy
        vm.prank(_OWNER);
        _baselineKernel.executeAction(BaselineKernelActions.ActivatePolicy, _dtlAddress);
        _;
    }

    modifier givenAllowlistParams(address tokenBalance_, uint96 tokenThreshold_) {
        _createData.allowlistParams = abi.encode(ITokenBalance(tokenBalance_), tokenThreshold_);
        _;
    }

    modifier givenTokenIsCreated() {
        _token = new MockERC20("Token", "TKN", 18);
        _;
    }

    modifier givenAccountHasTokenBalance(address account, uint256 balance) {
        _token.mint(account, balance);
        _;
    }
}
