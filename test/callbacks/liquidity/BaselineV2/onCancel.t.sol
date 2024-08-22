// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from "./BaselineAxisLaunchTest.sol";

import {BaseCallback} from "@axis-core-1.0.1/bases/BaseCallback.sol";
import {BaselineAxisLaunch} from
    "../../../../src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";

contract BaselineOnCancelTest is BaselineAxisLaunchTest {
    // ============ Modifiers ============ //

    // ============ Assertions ============ //

    // ============ Tests ============ //

    // [X] when the lot has not been registered
    //  [X] it reverts
    // [X] when the caller is not the auction house
    //  [X] it reverts
    // [X] when the lot has already been cancelled
    //  [X] it reverts
    // [X] when the lot has already been settled
    //  [X] it reverts
    // [X] when an insufficient quantity of the base token is transferred to the callback
    //  [X] it reverts
    // [X] it updates circulating supply, marks the auction as completed and burns the refunded base token quantity

    function test_lotNotRegistered_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAddressHasBaseTokenBalance(_dtlAddress, _LOT_CAPACITY)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the callback
        _onCancel();
    }

    function test_notAuctionHouse_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasBaseTokenBalance(_dtlAddress, _LOT_CAPACITY)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Perform callback
        _dtl.onCancel(_lotId, _LOT_CAPACITY, true, abi.encode(""));
    }

    function test_lotAlreadyCancelled_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasBaseTokenBalance(_dtlAddress, _LOT_CAPACITY)
        givenOnCancel
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_AlreadyComplete.selector);
        vm.expectRevert(err);

        // Perform callback
        _onCancel();
    }

    function test_lotAlreadySettled_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform onSettle callback
        _onSettle();

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_AlreadyComplete.selector);
        vm.expectRevert(err);

        // Perform callback
        _onCancel();
    }

    function test_insufficientRefund_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaselineAxisLaunch.Callback_MissingFunds.selector);
        vm.expectRevert(err);

        // Perform callback
        _onCancel();
    }

    function test_success()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
    {
        // Transfer capacity from auction house back to the callback
        // We transfer instead of minting to not affect the supply
        _transferBaseToken(_dtlAddress, _LOT_CAPACITY);

        // Perform callback
        _onCancel();

        // Check the circulating supply is updated
        assertEq(_baseToken.totalSupply(), 0, "circulating supply");

        // Check the auction is marked as completed
        assertEq(_dtl.auctionComplete(), true, "auction completed");

        // Check the refunded base token quantity is burned
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token: callback balance");
        assertEq(_baseToken.balanceOf(address(_baseToken)), 0, "base token: contract balance");

        // Transfer lock should be enabled
        assertEq(_baseToken.locked(), true, "transfer lock");
    }
}
