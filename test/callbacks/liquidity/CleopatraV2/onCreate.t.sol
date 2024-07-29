// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {CleopatraV2DirectToLiquidityTest} from "./CleopatraV2DTLTest.sol";

import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";
import {CleopatraV2DirectToLiquidity} from
    "../../../../src/callbacks/liquidity/Cleopatra/CleopatraV2DTL.sol";

contract CleopatraV2DTLOnCreateForkTest is CleopatraV2DirectToLiquidityTest {
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
    //  [X] it reverts
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
    // [X] given the pool fee is not enabled
    //  [X] it reverts
    // [X] given cleopatra v2 pool already exists
    //  [X] it succeeds
    // [X] when the vesting start timestamp is set
    //  [X] it reverts
    // [X] when the vesting expiry timestamp is set
    //  [X] it reverts
    // [X] when the recipient is the zero address
    //  [X] it reverts
    // [X] when the recipient is not the seller
    //  [X] it records the recipient
    // [ ] when the veRamTokenId is set
    //  [ ] given the DTL contract is approved to use the veRamTokenId
    //   [ ] it succeeds
    //  [ ] it reverts
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

    function test_givenPoolExists()
        public
        givenCallbackIsCreated
        givenPoolIsCreatedAndInitialized(0)
    {
        _performOnCreate();

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.active, true, "active");
    }

    function test_givenVestingStartParameterIsSet()
        public
        givenCallbackIsCreated
        givenVestingStart(_initialTimestamp + 1)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaseDirectToLiquidity.Callback_NotSupported.selector);
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_givenVestingExpiryParameterIsSet()
        public
        givenCallbackIsCreated
        givenVestingExpiry(_initialTimestamp + 1)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaseDirectToLiquidity.Callback_NotSupported.selector);
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_givenVestingStartAndExpiryParameterIsSet()
        public
        givenCallbackIsCreated
        givenVestingStart(_initialTimestamp + 1)
        givenVestingExpiry(_initialTimestamp + 2)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaseDirectToLiquidity.Callback_NotSupported.selector);
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_givenPoolFeeIsNotEnabled_reverts()
        public
        givenCallbackIsCreated
        givenPoolFee(0)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            CleopatraV2DirectToLiquidity.Callback_Params_PoolFeeNotEnabled.selector
        );
        vm.expectRevert(err);

        _performOnCreate();
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

        CleopatraV2DirectToLiquidity.CleopatraV2OnCreateParams memory _cleopatraCreateParams = abi
            .decode(configuration.implParams, (CleopatraV2DirectToLiquidity.CleopatraV2OnCreateParams));
        assertEq(_cleopatraCreateParams.poolFee, _cleopatraCreateParams.poolFee, "poolFee");
        assertEq(
            _cleopatraCreateParams.maxSlippage, _cleopatraCreateParams.maxSlippage, "maxSlippage"
        );
        // assertEq(_cleopatraCreateParams.veRamTokenId, _cleopatraCreateParams.veRamTokenId, "veRamTokenId");

        // Assert balances
        _assertBaseTokenBalances();
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

        // Assert balances
        _assertBaseTokenBalances();
    }

    function test_maxSlippage_fuzz(uint24 maxSlippage_) public givenCallbackIsCreated {
        uint24 maxSlippage = uint24(bound(maxSlippage_, 0, 100e2));
        _setMaxSlippage(maxSlippage);

        _performOnCreate();

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.implParams, _dtlCreateParams.implParams, "implParams");

        CleopatraV2DirectToLiquidity.CleopatraV2OnCreateParams memory cleopatraCreateParams = abi
            .decode(configuration.implParams, (CleopatraV2DirectToLiquidity.CleopatraV2OnCreateParams));
        assertEq(cleopatraCreateParams.maxSlippage, maxSlippage, "maxSlippage");
    }

    // function test_veRamTokenId()
    //     public
    //     givenCallbackIsCreated
    //     givenVeRamTokenId
    //     givenVeRamTokenIdApproval(true)
    // {
    //     _performOnCreate();

    //     // Assert values
    //     BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);

    //     CleopatraV2DirectToLiquidity.CleopatraV2OnCreateParams memory cleopatraCreateParams =
    //         abi.decode(configuration.implParams, (CleopatraV2DirectToLiquidity.CleopatraV2OnCreateParams));
    //     assertEq(cleopatraCreateParams.veRamTokenId, 1000, "veRamTokenId");
    // }

    // function test_veRamTokenId_notApproved_reverts()
    //     public
    //     givenCallbackIsCreated
    //     givenVeRamTokenId
    //     givenVeRamTokenIdApproval(false)
    // {
    //     // Expect revert
    //     bytes memory err = abi.encodeWithSelector(
    //         CleopatraV2DirectToLiquidity.Callback_Params_VeRamTokenIdNotApproved.selector
    //     );
    //     vm.expectRevert(err);

    //     _performOnCreate();
    // }
}
