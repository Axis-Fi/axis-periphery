// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from "./BaselineAxisLaunchTest.sol";

import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";

contract BaselineOnCurateTest is BaselineAxisLaunchTest {
    // ============ Modifiers ============ //

    // ============ Assertions ============ //

    // ============ Tests ============ //

    // [X] when the lot has not been registered
    //  [X] it reverts
    // [X] when the caller is not the auction house
    //  [X] it reverts
    // [X] when the curator fee is zero
    //  [X] it does nothing
    // [X] it mints the base token to the auction house

    function test_lotNotRegistered_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the callback
        _onCurate(0);
    }

    function test_notAuctionHouse_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Perform callback
        _dtl.onCurate(_lotId, 0, true, abi.encode(""));
    }

    function test_curatorFeeNonZero(
        uint256 curatorFee_
    ) public givenBPoolIsCreated givenCallbackIsCreated givenAuctionIsCreated givenOnCreate {
        uint256 curatorFee = bound(curatorFee_, 1, type(uint96).max);
        uint256 balanceBefore = _baseToken.balanceOf(address(_auctionHouse));

        // Perform callback
        _onCurate(curatorFee);

        // Assert that the base token was minted to the auction house
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            balanceBefore + curatorFee,
            "base token: auction house"
        );

        // Transfer lock should be disabled
        assertEq(_baseToken.locked(), false, "transfer lock");
    }

    function test_curatorFeeZero()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
    {
        uint256 balanceBefore = _baseToken.balanceOf(address(_auctionHouse));

        // Perform callback
        _onCurate(0);

        // Assert that the base token was minted to the auction house
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)), balanceBefore, "base token: auction house"
        );
    }
}
