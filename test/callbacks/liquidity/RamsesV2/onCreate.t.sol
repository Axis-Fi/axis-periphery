// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {RamsesV2DirectToLiquidityTest} from "./RamsesV2DTLTest.sol";

import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";
import {RamsesV2DirectToLiquidity} from "../../../../src/callbacks/liquidity/Ramses/RamsesV2DTL.sol";

contract RamsesV2DTLOnCreateForkTest is RamsesV2DirectToLiquidityTest {
    // ============ Modifiers ============ //

    function _performCallback(address seller_) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            seller_,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            false,
            abi.encode(_dtlCreateParams)
        );
    }

    function _performCallback() internal {
        _performCallback(_SELLER);
    }

    // ============ Assertions ============ //

    function _expectTransferFrom() internal {
        vm.expectRevert("TRANSFER_FROM_FAILED");
    }

    function _expectInvalidParams() internal {
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);
    }

    function _expectNotAuthorized() internal {
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);
    }

    function _assertBaseTokenBalances() internal view {
        assertEq(_baseToken.balanceOf(_SELLER), 0, "seller balance");
        assertEq(_baseToken.balanceOf(_NOT_SELLER), 0, "not seller balance");
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "dtl balance");
    }

    // ============ Tests ============ //

    // [X] when the callback data is incorrect
    //  [X] it reverts
    // [X] when the callback is not called by the auction house
    //  [X] it reverts
    // [X] when the lot has already been registered
    //  [X] it reverts
    // [X] when the proceeds utilisation is 0
    //  [X] it reverts
    // [X] when the proceeds utilisation is greater than 100%
    //  [X] it reverts
    // [ ] when the implParams is not the correct length
    //  [ ] it reverts
    // [ ] when the max slippage is between 0 and 100%
    //  [ ] it succeeds
    // [ ] when the max slippage is greater than 100%
    //  [ ] it reverts
    // [X] given the pool fee is not enabled
    //  [X] it reverts
    // [ ] given ramses v2 pool already exists
    //  [ ] it succeeds
    // [ ] when the vesting start timestamp is set
    //  [ ] it reverts
    // [ ] when the vesting expiry timestamp is set
    //  [ ] it reverts
    // [X] when the recipient is the zero address
    //  [X] it reverts
    // [X] when the recipient is not the seller
    //  [X] it records the recipient
    // [X] when multiple lots are created
    //  [X] it registers each lot
    // [X] it registers the lot

    function test_whenCallbackDataIsIncorrect_reverts() public givenCallbackIsCreated {
        // Expect revert
        vm.expectRevert();

        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            false,
            abi.encode(uint256(10))
        );
    }

    function test_whenCallbackIsNotCalledByAuctionHouse_reverts() public givenCallbackIsCreated {
        _expectNotAuthorized();

        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            false,
            abi.encode(_dtlCreateParams)
        );
    }

    function test_whenLotHasAlreadyBeenRegistered_reverts() public givenCallbackIsCreated {
        _performCallback();

        _expectInvalidParams();

        _performCallback();
    }

    function test_whenProceedsUtilisationIs0_reverts()
        public
        givenCallbackIsCreated
        givenProceedsUtilisationPercent(0)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_PercentOutOfBounds.selector, 0, 1, 100e2
        );
        vm.expectRevert(err);

        _performCallback();
    }

    function test_whenProceedsUtilisationIsGreaterThan100Percent_reverts()
        public
        givenCallbackIsCreated
        givenProceedsUtilisationPercent(100e2 + 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_PercentOutOfBounds.selector, 100e2 + 1, 1, 100e2
        );
        vm.expectRevert(err);

        _performCallback();
    }

    function test_givenPoolFeeIsNotEnabled_reverts()
        public
        givenCallbackIsCreated
        givenPoolFee(0)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            RamsesV2DirectToLiquidity.Callback_Params_PoolFeeNotEnabled.selector
        );
        vm.expectRevert(err);

        _performCallback();
    }

    function test_whenRecipientIsZeroAddress_reverts() public givenCallbackIsCreated {
        _dtlCreateParams.recipient = address(0);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaseDirectToLiquidity.Callback_Params_InvalidAddress.selector);
        vm.expectRevert(err);

        _performCallback();
    }

    function test_whenRecipientIsNotSeller_succeeds()
        public
        givenCallbackIsCreated
        whenRecipientIsNotSeller
    {
        _performCallback();

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.recipient, _NOT_SELLER, "recipient");

        // Assert balances
        _assertBaseTokenBalances();
    }

    function test_succeeds() public givenCallbackIsCreated {
        _performCallback();

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.recipient, _SELLER, "recipient");
        assertEq(configuration.lotCapacity, _LOT_CAPACITY, "lotCapacity");
        assertEq(configuration.lotCuratorPayout, 0, "lotCuratorPayout");
        assertEq(
            configuration.proceedsUtilisationPercent,
            _dtlCreateParams.proceedsUtilisationPercent,
            "proceedsUtilisationPercent"
        );
        assertEq(configuration.vestingStart, 0, "vestingStart");
        assertEq(configuration.vestingExpiry, 0, "vestingExpiry");
        assertEq(address(configuration.linearVestingModule), address(0), "linearVestingModule");
        assertEq(configuration.active, true, "active");
        assertEq(configuration.implParams, _dtlCreateParams.implParams, "implParams");

        RamsesV2DirectToLiquidity.RamsesV2OnCreateParams memory _ramsesCreateParams = abi.decode(
            _dtlCreateParams.implParams, (RamsesV2DirectToLiquidity.RamsesV2OnCreateParams)
        );
        assertEq(_ramsesCreateParams.poolFee, _ramsesCreateParams.poolFee, "poolFee");
        assertEq(_ramsesCreateParams.maxSlippage, _ramsesCreateParams.maxSlippage, "maxSlippage");
        assertEq(_ramsesCreateParams.veRamTokenId, _ramsesCreateParams.veRamTokenId, "veRamTokenId");

        // Assert balances
        _assertBaseTokenBalances();
    }

    function test_succeeds_multiple() public givenCallbackIsCreated {
        // Lot one
        _performCallback();

        // Lot two
        _dtlCreateParams.recipient = _NOT_SELLER;
        _lotId = 2;
        _performCallback(_NOT_SELLER);

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.recipient, _NOT_SELLER, "recipient");
        assertEq(configuration.lotCapacity, _LOT_CAPACITY, "lotCapacity");
        assertEq(configuration.lotCuratorPayout, 0, "lotCuratorPayout");
        assertEq(
            configuration.proceedsUtilisationPercent,
            _dtlCreateParams.proceedsUtilisationPercent,
            "proceedsUtilisationPercent"
        );
        assertEq(configuration.vestingStart, 0, "vestingStart");
        assertEq(configuration.vestingExpiry, 0, "vestingExpiry");
        assertEq(address(configuration.linearVestingModule), address(0), "linearVestingModule");
        assertEq(configuration.active, true, "active");
        assertEq(configuration.implParams, _dtlCreateParams.implParams, "implParams");

        // Assert balances
        _assertBaseTokenBalances();
    }
}
