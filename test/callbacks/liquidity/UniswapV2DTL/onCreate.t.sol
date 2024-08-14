// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV2DirectToLiquidityTest} from "./UniswapV2DTLTest.sol";

import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";
import {UniswapV2DirectToLiquidity} from "../../../../src/callbacks/liquidity/UniswapV2DTL.sol";

contract UniswapV2DirectToLiquidityOnCreateTest is UniswapV2DirectToLiquidityTest {
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
    // [X] given uniswap v2 pool already exists
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
    //  [X] given the vesting start timestamp is before the auction conclusion
    //   [X] it reverts
    //  [X] it records the address of the linear vesting module
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
        _performOnCreate();

        _expectInvalidParams();

        _performOnCreate();
    }

    function test_poolPercent_whenBelowBounds_reverts(
        uint24 poolPercent_
    ) public givenCallbackIsCreated {
        uint24 poolPercent = uint24(bound(poolPercent_, 0, 10e2 - 1));

        // Set pool percent
        _setPoolPercent(poolPercent);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_PercentOutOfBounds.selector,
            poolPercent,
            10e2,
            100e2
        );
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_poolPercent_whenAboveBounds_reverts(
        uint24 poolPercent_
    ) public givenCallbackIsCreated {
        uint24 poolPercent = uint24(bound(poolPercent_, 100e2 + 1, type(uint24).max));

        // Set pool percent
        _setPoolPercent(poolPercent);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_PercentOutOfBounds.selector,
            poolPercent,
            10e2,
            100e2
        );
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_poolPercent_fuzz(uint24 poolPercent_) public givenCallbackIsCreated {
        uint24 poolPercent = uint24(bound(poolPercent_, 10e2, 100e2));

        _setPoolPercent(poolPercent);

        _performOnCreate();

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.poolPercent, poolPercent, "poolPercent");
    }

    function test_paramsIncorrectLength_reverts() public givenCallbackIsCreated {
        // Set the implParams to an incorrect length
        _dtlCreateParams.implParams = abi.encode(uint256(10), uint256(10));

        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_maxSlippageGreaterThan100Percent_reverts(
        uint24 maxSlippage_
    ) public givenCallbackIsCreated {
        uint24 maxSlippage = uint24(bound(maxSlippage_, 100e2 + 1, type(uint24).max));
        _setMaxSlippage(maxSlippage);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_PercentOutOfBounds.selector, maxSlippage, 0, 100e2
        );
        vm.expectRevert(err);

        _performOnCreate();
    }

    function test_maxSlippage_fuzz(uint24 maxSlippage_) public givenCallbackIsCreated {
        uint24 maxSlippage = uint24(bound(maxSlippage_, 0, 100e2));
        _setMaxSlippage(maxSlippage);

        _performOnCreate();

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.implParams, _dtlCreateParams.implParams, "implParams");

        UniswapV2DirectToLiquidity.UniswapV2OnCreateParams memory uniswapV2CreateParams = abi.decode(
            _dtlCreateParams.implParams, (UniswapV2DirectToLiquidity.UniswapV2OnCreateParams)
        );
        assertEq(uniswapV2CreateParams.maxSlippage, maxSlippage, "maxSlippage");
    }

    function test_givenUniswapV2PoolAlreadyExists() public givenCallbackIsCreated {
        // Create the pool
        _uniV2Factory.createPair(address(_baseToken), address(_quoteToken));

        // Perform the callback
        _performOnCreate();

        // Assert that the callback was successful
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.active, true, "active");
    }

    function test_whenStartAndExpiryTimestampsAreTheSame_reverts()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_AUCTION_CONCLUSION + 1)
        givenVestingExpiry(_AUCTION_CONCLUSION + 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_InvalidVestingParams.selector
        );

        _createLot(address(_SELLER), err);
    }

    function test_whenStartTimestampIsAfterExpiryTimestamp_reverts()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_AUCTION_CONCLUSION + 2)
        givenVestingExpiry(_AUCTION_CONCLUSION + 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_InvalidVestingParams.selector
        );

        _createLot(address(_SELLER), err);
    }

    function test_whenStartTimestampIsBeforeCurrentTimestamp_reverts()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_START - 1)
        givenVestingExpiry(_START + 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_InvalidVestingParams.selector
        );

        _createLot(address(_SELLER), err);
    }

    function test_whenExpiryTimestampIsBeforeCurrentTimestamp_reverts()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_AUCTION_CONCLUSION + 1)
        givenVestingExpiry(_AUCTION_CONCLUSION - 1)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_InvalidVestingParams.selector
        );

        _createLot(address(_SELLER), err);
    }

    function test_whenVestingSpecified_givenLinearVestingModuleNotInstalled_reverts()
        public
        givenCallbackIsCreated
        givenVestingStart(_AUCTION_CONCLUSION + 1)
        givenVestingExpiry(_AUCTION_CONCLUSION + 2)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_LinearVestingModuleNotFound.selector
        );

        _createLot(address(_SELLER), err);
    }

    function test_whenVestingSpecified_whenStartTimestampIsBeforeAuctionConclusion_reverts()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_AUCTION_CONCLUSION - 1)
        givenVestingExpiry(_AUCTION_CONCLUSION + 2)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_Params_InvalidVestingParams.selector
        );

        _createLot(address(_SELLER), err);
    }

    function test_whenVestingSpecified_whenVestingStartTimestampIsOnAuctionConclusion()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_AUCTION_CONCLUSION)
        givenVestingExpiry(_AUCTION_CONCLUSION + 2)
    {
        _lotId = _createLot(address(_SELLER));

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.vestingStart, _AUCTION_CONCLUSION, "vestingStart");
        assertEq(configuration.vestingExpiry, _AUCTION_CONCLUSION + 2, "vestingExpiry");
        assertEq(
            address(configuration.linearVestingModule),
            address(_linearVesting),
            "linearVestingModule"
        );

        // Assert balances
        _assertBaseTokenBalances();
    }

    function test_whenVestingSpecified()
        public
        givenCallbackIsCreated
        givenLinearVestingModuleIsInstalled
        givenVestingStart(_AUCTION_CONCLUSION + 1)
        givenVestingExpiry(_AUCTION_CONCLUSION + 2)
    {
        _lotId = _createLot(address(_SELLER));

        // Assert values
        BaseDirectToLiquidity.DTLConfiguration memory configuration = _getDTLConfiguration(_lotId);
        assertEq(configuration.vestingStart, _AUCTION_CONCLUSION + 1, "vestingStart");
        assertEq(configuration.vestingExpiry, _AUCTION_CONCLUSION + 2, "vestingExpiry");
        assertEq(
            address(configuration.linearVestingModule),
            address(_linearVesting),
            "linearVestingModule"
        );

        // Assert balances
        _assertBaseTokenBalances();
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
        assertEq(configuration.poolPercent, _dtlCreateParams.poolPercent, "poolPercent");
        assertEq(configuration.vestingStart, 0, "vestingStart");
        assertEq(configuration.vestingExpiry, 0, "vestingExpiry");
        assertEq(address(configuration.linearVestingModule), address(0), "linearVestingModule");
        assertEq(configuration.active, true, "active");
        assertEq(configuration.implParams, _dtlCreateParams.implParams, "implParams");

        UniswapV2DirectToLiquidity.UniswapV2OnCreateParams memory uniswapV2CreateParams = abi.decode(
            _dtlCreateParams.implParams, (UniswapV2DirectToLiquidity.UniswapV2OnCreateParams)
        );
        assertEq(
            uniswapV2CreateParams.maxSlippage, _uniswapV2CreateParams.maxSlippage, "maxSlippage"
        );

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
        assertEq(configuration.poolPercent, _dtlCreateParams.poolPercent, "poolPercent");
        assertEq(configuration.vestingStart, 0, "vestingStart");
        assertEq(configuration.vestingExpiry, 0, "vestingExpiry");
        assertEq(address(configuration.linearVestingModule), address(0), "linearVestingModule");
        assertEq(configuration.active, true, "active");
        assertEq(configuration.implParams, _dtlCreateParams.implParams, "implParams");

        UniswapV2DirectToLiquidity.UniswapV2OnCreateParams memory uniswapV2CreateParams = abi.decode(
            _dtlCreateParams.implParams, (UniswapV2DirectToLiquidity.UniswapV2OnCreateParams)
        );
        assertEq(
            uniswapV2CreateParams.maxSlippage, _uniswapV2CreateParams.maxSlippage, "maxSlippage"
        );

        // Assert balances
        _assertBaseTokenBalances();
    }
}
