// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {RamsesV1DirectToLiquidityTest} from "./RamsesV1DTLTest.sol";

import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";

contract RamsesV1DTLOnCancelForkTest is RamsesV1DirectToLiquidityTest {
    uint96 internal constant _REFUND_AMOUNT = 2e18;

    // ============ Modifiers ============ //

    function _performCallback(uint96 lotId_) internal {
        _performOnCancel(lotId_, _REFUND_AMOUNT);
    }

    // ============ Tests ============ //

    // [X] given the onCancel callback has already been called
    //  [X] when onSettle is called
    //   [X] it reverts
    //  [X] when onCancel is called
    //   [X] it reverts
    //  [X] when onCurate is called
    //   [X] it reverts
    //  [X] when onCreate is called
    //   [X] it reverts
    // [X] when the lot has not been registered
    //  [X] it reverts
    // [X] when multiple lots are created
    //  [X] it marks the correct lot as inactive
    // [X] it marks the lot as inactive

    function test_whenLotNotRegistered_reverts() public givenCallbackIsCreated {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the function
        _performCallback(_lotId);
    }

    function test_success() public givenCallbackIsCreated givenOnCreate {
        // Call the function
        _performCallback(_lotId);

        // Check the values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.active, false, "active");

        // Check the balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token balance");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller base token balance");
        assertEq(_baseToken.balanceOf(_NOT_SELLER), 0, "not seller base token balance");
    }

    function test_success_multiple() public givenCallbackIsCreated givenOnCreate {
        uint96 lotIdOne = _lotId;

        // Create a second lot and cancel it
        uint96 lotIdTwo = _createLot(_NOT_SELLER);
        _performCallback(lotIdTwo);

        // Check the values
        BaseDirectToLiquidity.DTLConfiguration memory configurationOne =
            _getDTLConfiguration(lotIdOne);
        assertEq(configurationOne.active, true, "lot one: active");

        BaseDirectToLiquidity.DTLConfiguration memory configurationTwo =
            _getDTLConfiguration(lotIdTwo);
        assertEq(configurationTwo.active, false, "lot two: active");

        // Check the balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token balance");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller base token balance");
        assertEq(_baseToken.balanceOf(_NOT_SELLER), 0, "not seller base token balance");
    }

    function test_auctionCancelled_onCreate_reverts() public givenCallbackIsCreated givenOnCreate {
        // Call the function
        _performCallback(_lotId);

        // Expect revert
        // BaseCallback determines if the lot has already been registered
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_auctionCancelled_onCurate_reverts() public givenCallbackIsCreated givenOnCreate {
        // Call the function
        _performCallback(_lotId);

        // Expect revert
        // BaseDirectToLiquidity determines if the lot has already been completed
        bytes memory err =
            abi.encodeWithSelector(BaseDirectToLiquidity.Callback_AlreadyComplete.selector);
        vm.expectRevert(err);

        _performOnCurate(0);
    }

    function test_auctionCancelled_onCancel_reverts() public givenCallbackIsCreated givenOnCreate {
        // Call the function
        _performCallback(_lotId);

        // Expect revert
        // BaseDirectToLiquidity determines if the lot has already been completed
        bytes memory err =
            abi.encodeWithSelector(BaseDirectToLiquidity.Callback_AlreadyComplete.selector);
        vm.expectRevert(err);

        _performOnCancel();
    }

    function test_auctionCancelled_onSettle_reverts() public givenCallbackIsCreated givenOnCreate {
        // Call the function
        _performCallback(_lotId);

        // Expect revert
        // BaseDirectToLiquidity determines if the lot has already been completed
        bytes memory err =
            abi.encodeWithSelector(BaseDirectToLiquidity.Callback_AlreadyComplete.selector);
        vm.expectRevert(err);

        _performOnSettle();
    }
}
