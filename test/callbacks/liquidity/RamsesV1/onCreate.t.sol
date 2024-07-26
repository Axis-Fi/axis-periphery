// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {RamsesV1DirectToLiquidityTest} from "./RamsesV1DTLTest.sol";

import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";
import {RamsesV1DirectToLiquidity} from "../../../../src/callbacks/liquidity/Ramses/RamsesV1DTL.sol";

contract RamsesV1DTLOnCreateForkTest is RamsesV1DirectToLiquidityTest {
    // ============ Modifiers ============ //

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
    //  [ X] it reverts
    // [X] when the callback is not called by the auction house
    //  [X] it reverts
    // [X] when the lot has already been registered
    //  [X] it reverts
    // [X] when the proceeds utilisation is 0
    //  [X] it reverts
    // [X] when the proceeds utilisation is greater than 100%
    //  [X] it reverts
    // [X] when the implParams is not the correct length
    //  [X] it reverts
    // [X] when the max slippage is between 0 and 100%
    //  [X] it succeeds
    // [X] when the max slippage is greater than 100%
    //  [X] it reverts
    // [X] given ramses v1 pool stable already exists
    //  [X] it succeeds
    // [X] given ramses v1 pool volatile already exists
    //  [X] it succeeds
    // [X] when the start and expiry timestamps are the same
    //  [X] it reverts
    // [X] when the start timestamp is after the expiry timestamp
    //  [X] it reverts
    // [X] when the start timestamp is before the current timestamp
    //  [X] it succeeds
    // [X] when the expiry timestamp is before the current timestamp
    //  [X] it reverts
    // [X] when the start timestamp and expiry timestamp are specified
    //  [X] given the linear vesting module is not installed
    //   [X] it reverts
    //  [X] it records the address of the linear vesting module
    // [X] when the recipient is the zero address
    //  [X] it reverts
    // [X] when the recipient is not the seller
    //  [X] it records the recipient
    // [X] when multiple lots are created
    //  [X] it registers each lot
    // [X] it registers the lot, stores the parameters

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
        _performOnCreate();

        _expectInvalidParams();

        _performOnCreate();
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

        _performOnCreate();
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

        _performOnCreate();
    }

    function test_paramsIncorrectLength_reverts() public givenCallbackIsCreated {
        // Set the implParams to an incorrect length
        _dtlCreateParams.implParams = abi.encode(uint256(10));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_maxSlippageGreaterThan100Percent_reverts(uint24 maxSlippage_)
        public
        givenCallbackIsCreated
    {
        uint24 maxSlippage = uint24(bound(maxSlippage_, 100e2 + 1, type(uint24).max));
        _setMaxSlippage(maxSlippage);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_PercentOutOfBounds.selector, maxSlippage, 0, 100e2
        );
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_whenStartAndExpiryTimestampsAreTheSame_reverts()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_initialTimestamp + 1)
        givenVestingExpiry(_initialTimestamp + 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_InvalidVestingParams.selector
        );
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_whenStartTimestampIsAfterExpiryTimestamp_reverts()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_initialTimestamp + 2)
        givenVestingExpiry(_initialTimestamp + 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_InvalidVestingParams.selector
        );
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_whenStartTimestampIsBeforeCurrentTimestamp_succeeds()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_initialTimestamp - 1)
        givenVestingExpiry(_initialTimestamp + 1)
    {
        _performOnCreate();

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.vestingStart, _initialTimestamp - 1, "vestingStart");
        assertEq(configuration.vestingExpiry, _initialTimestamp + 1, "vestingExpiry");
        assertEq(
            address(configuration.linearVestingModule),
            address(_linearVesting),
            "linearVestingModule"
        );

        // Assert balances
        _assertBaseTokenBalances();
    }

    function test_whenExpiryTimestampIsBeforeCurrentTimestamp_reverts()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_initialTimestamp + 1)
        givenVestingExpiry(_initialTimestamp - 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_InvalidVestingParams.selector
        );
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_whenVestingSpecified_givenLinearVestingModuleNotInstalled_reverts()
        public
        givenCallbackIsCreated
        givenVestingStart(_initialTimestamp + 1)
        givenVestingExpiry(_initialTimestamp + 2)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_LinearVestingModuleNotFound.selector
        );
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_whenVestingSpecified()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_initialTimestamp + 1)
        givenVestingExpiry(_initialTimestamp + 2)
    {
        _performOnCreate();

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.vestingStart, _initialTimestamp + 1, "vestingStart");
        assertEq(configuration.vestingExpiry, _initialTimestamp + 2, "vestingExpiry");
        assertEq(
            address(configuration.linearVestingModule),
            address(_linearVesting),
            "linearVestingModule"
        );

        // Assert balances
        _assertBaseTokenBalances();

        _assertApprovals();
    }

    function test_whenRecipientIsZeroAddress_reverts() public givenCallbackIsCreated {
        _dtlCreateParams.recipient = address(0);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaseDirectToLiquidity.Callback_Params_InvalidAddress.selector);
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_whenRecipientIsNotSeller_succeeds()
        public
        givenCallbackIsCreated
        whenRecipientIsNotSeller
    {
        _performOnCreate();

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.recipient, _NOT_SELLER, "recipient");

        // Assert balances
        _assertBaseTokenBalances();
    }

    function test_succeeds() public givenCallbackIsCreated {
        _performOnCreate();

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

        RamsesV1DirectToLiquidity.RamsesV1OnCreateParams memory ramsesCreateParams = abi.decode(
            _dtlCreateParams.implParams, (RamsesV1DirectToLiquidity.RamsesV1OnCreateParams)
        );
        assertEq(ramsesCreateParams.stable, _ramsesCreateParams.stable, "stable");
        assertEq(ramsesCreateParams.maxSlippage, _ramsesCreateParams.maxSlippage, "maxSlippage");

        // Assert balances
        _assertBaseTokenBalances();

        _assertApprovals();
    }

    function test_succeeds_multiple() public givenCallbackIsCreated {
        // Lot one
        _performOnCreate();

        // Lot two
        _dtlCreateParams.recipient = _NOT_SELLER;
        _lotId = 2;
        _performOnCreate(_NOT_SELLER);

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

        RamsesV1DirectToLiquidity.RamsesV1OnCreateParams memory ramsesCreateParams = abi.decode(
            _dtlCreateParams.implParams, (RamsesV1DirectToLiquidity.RamsesV1OnCreateParams)
        );
        assertEq(ramsesCreateParams.stable, _ramsesCreateParams.stable, "stable");
        assertEq(ramsesCreateParams.maxSlippage, _ramsesCreateParams.maxSlippage, "maxSlippage");

        // Assert balances
        _assertBaseTokenBalances();

        _assertApprovals();
    }

    function test_maxSlippage_fuzz(uint24 maxSlippage_) public givenCallbackIsCreated {
        uint24 maxSlippage = uint24(bound(maxSlippage_, 0, 100e2));
        _setMaxSlippage(maxSlippage);

        _performOnCreate();

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.implParams, _dtlCreateParams.implParams, "implParams");

        RamsesV1DirectToLiquidity.RamsesV1OnCreateParams memory ramsesCreateParams = abi.decode(
            _dtlCreateParams.implParams, (RamsesV1DirectToLiquidity.RamsesV1OnCreateParams)
        );
        assertEq(ramsesCreateParams.stable, _ramsesCreateParams.stable, "stable");
        assertEq(ramsesCreateParams.maxSlippage, maxSlippage, "maxSlippage");
    }

    function test_givenStablePoolExists() public givenCallbackIsCreated {
        // Create the pool
        _factory.createPair(address(_baseToken), address(_quoteToken), true);

        _performOnCreate();

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.active, true, "active");
    }

    function test_givenVolatilePoolExists() public givenCallbackIsCreated {
        // Create the pool
        _factory.createPair(address(_baseToken), address(_quoteToken), false);

        _performOnCreate();

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.active, true, "active");
    }
}