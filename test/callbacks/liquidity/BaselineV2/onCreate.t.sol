// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from "./BaselineAxisLaunchTest.sol";

import {BaselineAxisLaunch} from
    "../../../../src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {Range} from "@baseline/modules/BPOOL.v1.sol";
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";

import {console2} from "@forge-std-1.9.1/console2.sol";

contract BaselineOnCreateTest is BaselineAxisLaunchTest {
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
        assertEq(
            _baseToken.balanceOf(address(_auctionHouse)),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            "auction house balance"
        );
    }

    // ============ Helper Functions ============ //

    /// @notice Returns the tick equivalent to the fixed price of the auction
    /// @dev    This function contains pre-calculated tick values, to prevent the implementation and tests using the same library.
    ///
    ///         This function also handles a set number of decimal permutations.
    function _getFixedPriceTick() internal view returns (int24) {
        // Calculation source: https://blog.uniswap.org/uniswap-v3-math-primer#how-does-tick-and-tick-spacing-relate-to-sqrtpricex96

        // Quote token is token1
        if (address(_quoteToken) > address(_baseToken)) {
            if (_quoteTokenDecimals == 18 && _baseTokenDecimals == 18) {
                // Fixed price = 3e18
                // SqrtPriceX96 = sqrt(3e18 * 2^192 / 1e18)
                //              = 1.3722720287e29
                // Tick = log((1.3722720287e29 / 2^96)^2) / log(1.0001)
                //      = 10,986.672184372 (rounded down)
                // Price = 1.0001^10986 / (10^(18-18)) = 2.9997983618
                return 10_986;
            }

            if (_quoteTokenDecimals == 18 && _baseTokenDecimals == 17) {
                // Fixed price = 3e18
                // SqrtPriceX96 = sqrt(3e18 * 2^192 / 1e17)
                //              = 4.3395051823e29
                // Tick = log((4.3395051823e29 / 2^96)^2) / log(1.0001)
                //      = 34,013.6743980767 (rounded down)
                // Price = 1.0001^34013 / (10^(18-17)) = 2.9997977008
                return 34_013;
            }

            if (_quoteTokenDecimals == 18 && _baseTokenDecimals == 19) {
                // Fixed price = 3e18
                // SqrtPriceX96 = sqrt(3e18 * 2^192 / 1e19)
                //              = 4.3395051799e28
                // Tick = log((4.3395051799e28 / 2^96)^2) / log(1.0001)
                //      = -12,040.3300194873 (rounded down)
                // Price = 1.0001^-12041 / (10^(18-19)) = 2.9997990227
                return -12_041;
            }

            revert("Unsupported decimal permutation");
        }

        // Quote token is token0
        if (_quoteTokenDecimals == 18 && _baseTokenDecimals == 18) {
            // Fixed price = 3e18
            // SqrtPriceX96 = sqrt(1e18 * 2^192 / 3e18)
            //              = 4.574240096e28
            // Tick = log((4.574240096e28 / 2^96)^2) / log(1.0001)
            //      = -10,986.6721814657 (rounded down)
            // Price = 1.0001^-10987 / (10^(18-18)) = 0.3333224068 = 0.3 base token per 1 quote token
            return -10_987;
        }

        if (_quoteTokenDecimals == 18 && _baseTokenDecimals == 17) {
            // Fixed price = 3e18
            // SqrtPriceX96 = sqrt(1e17 * 2^192 / 3e18)
            //              = 1.4465017266e28
            // Tick = log((1.4465017266e28 / 2^96)^2) / log(1.0001)
            //      = -34,013.6743872434 (rounded down)
            // Price = 1.0001^-34014 / (10^(17-18)) = 0.3333224803 = 0.3 base token per 1 quote token
            return -34_014;
        }

        if (_quoteTokenDecimals == 18 && _baseTokenDecimals == 19) {
            // Fixed price = 3e18
            // SqrtPriceX96 = sqrt(1e19 * 2^192 / 3e18)
            //              = 1.4465017267e29
            // Tick = log((1.4465017267e29 / 2^96)^2) / log(1.0001)
            //      = 12,040.3300206416 (rounded down)
            // Price = 1.0001^12040 / (10^(19-18)) = 0.3333223334 = 0.3 base token per 1 quote token
            return 12_040;
        }

        revert("Unsupported decimal permutation");
    }

    function _roundToTickSpacingUp(int24 activeTick_) internal view returns (int24) {
        // Rounds down
        int24 roundedTick = (activeTick_ / _tickSpacing) * _tickSpacing;

        // Add a tick spacing to round up
        // This mimics BPOOL.getActiveTS()
        if (activeTick_ >= 0 || activeTick_ % _tickSpacing == 0) {
            roundedTick += _tickSpacing;
        }

        return roundedTick;
    }

    function _getPoolActiveTick() internal view returns (int24) {
        (, int24 activeTick,,,,,) = _baseToken.pool().slot0();
        return activeTick;
    }

    function _assertTicks(int24 fixedPriceTick_) internal view {
        // Get the tick from the pool
        int24 activeTick = _getPoolActiveTick();

        assertEq(activeTick, fixedPriceTick_, "active tick");
        console2.log("Active tick: ", activeTick);
        console2.log("Tick spacing: ", _tickSpacing);

        // Calculate the active tick with rounding
        int24 anchorTickUpper = _roundToTickSpacingUp(fixedPriceTick_);
        int24 anchorTickLower = anchorTickUpper - _createData.anchorTickWidth * _tickSpacing;
        console2.log("Calculated anchor tick lower: ", anchorTickLower);
        console2.log("Calculated anchor tick upper: ", anchorTickUpper);

        // Anchor range should be the width of anchorTickWidth * tick spacing
        (int24 anchorTickLower_, int24 anchorTickUpper_) = _baseToken.getTicks(Range.ANCHOR);
        assertEq(anchorTickLower_, anchorTickLower, "anchor tick lower");
        assertEq(anchorTickUpper_, anchorTickUpper, "anchor tick upper");

        // Active tick should be within the anchor range
        assertGt(fixedPriceTick_, anchorTickLower_, "active tick > anchor tick lower");
        assertLe(fixedPriceTick_, anchorTickUpper_, "active tick <= anchor tick upper");

        // Floor range should be the width of the tick spacing and below the anchor range
        (int24 floorTickLower, int24 floorTickUpper) = _baseToken.getTicks(Range.FLOOR);
        assertEq(floorTickLower, anchorTickLower_ - _tickSpacing, "floor tick lower");
        assertEq(floorTickUpper, anchorTickLower_, "floor tick upper");

        // Discovery range should be the width of discoveryTickWidth * tick spacing and above the active tick
        (int24 discoveryTickLower, int24 discoveryTickUpper) = _baseToken.getTicks(Range.DISCOVERY);
        assertEq(discoveryTickLower, anchorTickUpper_, "discovery tick lower");
        assertEq(
            discoveryTickUpper,
            anchorTickUpper_ + _DISCOVERY_TICK_WIDTH * _tickSpacing,
            "discovery tick upper"
        );
    }

    // ============ Tests ============ //

    // [X] when the callback data is incorrect
    //  [X] it reverts
    // [X] when the callback is not called by the auction house
    //  [X] it reverts
    // [X] when the lot has already been registered
    //  [X] it reverts
    // [X] when the base token is not the BPOOL
    //  [X] it reverts
    // [X] when the quote token is not the reserve
    //  [X] it reverts
    // [X] when the base token is higher than the reserve token
    //  [X] it reverts
    // [X] when the recipient is the zero address
    //  [X] it reverts
    // [X] when the poolPercent is < 1%
    //  [X] it reverts
    // [X] when the poolPercent is > 100%
    //  [X] it reverts
    // [X] when the floorReservesPercent is not between 0 and 99%
    //  [X] it reverts
    // [X] when the anchorTickWidth is <= 0
    //  [X] it reverts
    // [X] when the auction format is not FPB
    //  [X] it reverts
    // [X] when the auction is not prefunded
    //  [X] it reverts
    // [X] when the floor reserves are too low
    //  [X] it reverts due to the solvency check
    // [X] when the floor reserves are too high
    //  [X] it reverts due to the solvency check
    // [X] when the pool percent is too low
    //  [X] it reverts due to the solvency check
    // [X] when the pool percent is too high
    //  [X] it reverts due to the solvency check
    // [X] when the floorReservesPercent is 0-99%
    //  [X] it correctly records the allocation
    // [X] when the tick spacing is narrow
    //  [X] the ticks do not overlap
    // [X] when the auction fixed price is very high
    //  [X] it handles the active tick correctly
    // [X] when the auction fixed price is very low
    //  [X] it handles the active tick correctly
    // [X] when the quote token decimals are higher than the base token decimals
    //  [X] it handles it correctly
    // [X] when the quote token decimals are lower than the base token decimals
    //  [X] it handles it correctly
    // [X] when the anchorTickWidth is small
    //  [X] it correctly sets the anchor ticks to not overlap with the other ranges
    // [X] when the anchorTickWidth is greater than 10
    //  [X] it reverts
    // [X] when the activeTick and anchorTickWidth results in an overflow
    //  [X] it reverts
    // [X] when the activeTick and anchorTickWidth results in an underflow
    //  [X] it reverts
    // [X] when the activeTick and discoveryTickWidth results in an overflow
    //  [X] it reverts
    // [X] when the activeTick and discoveryTickWidth results in an underflow
    //  [X] it reverts
    // [X] it transfers the base token to the auction house, updates circulating supply, sets the state variables, initializes the pool and sets the tick ranges

    function test_callbackDataIncorrect_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Expect revert
        vm.expectRevert();

        // Perform the call
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            true,
            abi.encode(uint256(10), uint256(20))
        );
    }

    function test_notAuctionHouse_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Expect revert
        _expectNotAuthorized();

        // Perform the call
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            true,
            abi.encode(_createData)
        );
    }

    function test_lotAlreadyRegistered_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Perform callback
        _onCreate();

        // Expect revert
        _expectInvalidParams();

        // Perform the callback again
        _onCreate();
    }

    function test_baseTokenNotBPool_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaselineAxisLaunch.Callback_Params_BAssetTokenMismatch.selector,
            address(_quoteToken),
            address(_baseToken)
        );
        vm.expectRevert(err);

        // Perform the call
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_quoteToken), // Will revert as the quote token != BPOOL
            address(_quoteToken),
            _LOT_CAPACITY,
            true,
            abi.encode(_createData)
        );
    }

    function test_quoteTokenNotReserve_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaselineAxisLaunch.Callback_Params_ReserveTokenMismatch.selector,
            address(_baseToken),
            address(_quoteToken)
        );
        vm.expectRevert(err);

        // Perform the call
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_baseToken), // Will revert as the base token != RESERVE
            _LOT_CAPACITY,
            true,
            abi.encode(_createData)
        );
    }

    function test_floorReservesPercentInvalid_reverts(uint24 floorReservesPercent_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        uint24 floorReservesPercent =
            uint24(bound(floorReservesPercent_, _NINETY_NINE_PERCENT + 1, type(uint24).max));
        _createData.floorReservesPercent = floorReservesPercent;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaselineAxisLaunch.Callback_Params_InvalidFloorReservesPercent.selector
        );
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_anchorTickWidth_belowZero_reverts(int24 anchorTickWidth_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        int24 anchorTickWidth = int24(bound(anchorTickWidth_, type(int24).min, 0));
        _createData.anchorTickWidth = anchorTickWidth;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaselineAxisLaunch.Callback_Params_InvalidAnchorTickWidth.selector
        );
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_anchorTickWidth_aboveTen_reverts(int24 anchorTickWidth_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        int24 anchorTickWidth = int24(bound(anchorTickWidth_, 11, type(int24).max));
        _createData.anchorTickWidth = anchorTickWidth;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaselineAxisLaunch.Callback_Params_InvalidAnchorTickWidth.selector
        );
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_recipientZero_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Set the recipient to be the zero address
        _createData.recipient = address(0);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_Params_InvalidRecipient.selector);
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_poolPercent_belowBounds_reverts(uint24 poolPercent_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        uint24 poolPercent = uint24(bound(poolPercent_, 0, 10e2 - 1));
        _setPoolPercent(poolPercent);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_Params_InvalidPoolPercent.selector);
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_poolPercent_aboveBounds_reverts(uint24 poolPercent_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        uint24 poolPercent = uint24(bound(poolPercent_, 100e2 + 1, type(uint24).max));
        _setPoolPercent(poolPercent);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_Params_InvalidPoolPercent.selector);
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_givenAuctionFormatNotFixedPriceBatch_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionFormatIsEmp
        givenAuctionIsCreated
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaselineAxisLaunch.Callback_Params_UnsupportedAuctionFormat.selector
        );
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_auctionNotPrefunded_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaselineAxisLaunch.Callback_Params_UnsupportedAuctionFormat.selector
        );
        vm.expectRevert(err);

        // Perform the call
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            false, // Will revert as the auction is not prefunded
            abi.encode(_createData)
        );
    }

    function test_auctionPriceDoesNotMatchPoolActiveTick()
        public
        givenBPoolIsCreated // BPOOL will have an active tick of _FIXED_PRICE
        givenCallbackIsCreated
        givenFixedPrice(25e17)
        givenAuctionIsCreated // Has to be after the fixed price is set
        givenPoolPercent(98e2) // For the solvency check
        givenFloorReservesPercent(99e2) // For the solvency check
    {
        // Perform the call
        _onCreate();

        // Check that the callback owner is correct
        assertEq(_dtl.owner(), _OWNER, "owner");

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(_baseToken.totalSupply(), _LOT_CAPACITY, "circulating supply");

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        // Fixed price = 2e18
        // SqrtPriceX96 = sqrt(2e18 * 2^192 / 1e18)
        //              = 1.12045542e29
        // Tick = log((1.12045542e29 / 2^96)^2) / log(1.0001)
        //      = 6,931.8183824009 (rounded down)
        // Price = 1.0001^6931 / (10^(18-18)) = 1.9998363402
        int24 fixedPriceTick = 10_986; // Price: 3e18

        _assertTicks(fixedPriceTick);
    }

    function test_success()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Perform the call
        _onCreate();

        // Check that the callback owner is correct
        assertEq(_dtl.owner(), _OWNER, "owner");

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(_baseToken.totalSupply(), _LOT_CAPACITY, "circulating supply");

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();

        _assertTicks(fixedPriceTick);

        // Transfer lock should be disabled
        assertEq(_baseToken.locked(), false, "transfer lock");
    }

    function test_floorReservesPercent_zero()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenFloorReservesPercent(0)
        givenPoolPercent(91e2) // For the solvency check
    {
        // Perform the call
        _onCreate();

        // Assert
        assertEq(_dtl.floorReservesPercent(), 0, "floor reserves percent");
    }

    function test_floorReservesPercent_zero_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenFloorReservesPercent(0)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_InvalidInitialization.selector);
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_floorReservesPercent_fiftyPercent()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenFloorReservesPercent(50e2)
    {
        // Perform the call
        _onCreate();

        // Assert
        assertEq(_dtl.floorReservesPercent(), 50e2, "floor reserves percent");
    }

    function test_floorReservesPercent_ninetyNinePercent()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenFloorReservesPercent(99e2)
        givenPoolPercent(82e2) // For the solvency check
    {
        // Perform the call
        _onCreate();

        // Assert
        assertEq(_dtl.floorReservesPercent(), 99e2, "floor reserves percent");
    }

    function test_floorReservesPercent_ninetyNine_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenFloorReservesPercent(99e2)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_InvalidInitialization.selector);
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_poolPercent_lowPercent()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenFixedPrice(25e18) // For the solvency check
        givenAuctionIsCreated
        givenPoolPercent(10e2)
        givenFloorReservesPercent(90e2) // For the solvency check
    {
        // Perform the call
        _onCreate();

        // Assert
        assertEq(_dtl.poolPercent(), 10e2, "pool percent");
    }

    function test_poolPercent_lowPercent_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenPoolPercent(10e2)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_InvalidInitialization.selector);
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_poolPercent_highPercent()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenPoolPercent(92e2)
        givenFloorReservesPercent(1) // For the solvency check
    {
        // Perform the call
        _onCreate();

        // Assert
        assertEq(_dtl.poolPercent(), 92e2, "pool percent");
    }

    function test_poolPercent_highPercent_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenPoolPercent(99e2)
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_InvalidInitialization.selector);
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_tickSpacingNarrow()
        public
        givenBPoolFeeTier(500)
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenPoolPercent(100e2) // For the solvency check
    {
        // Perform the call
        _onCreate();

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();

        _assertTicks(fixedPriceTick);
    }

    function test_auctionHighPrice()
        public
        givenFixedPrice(1e32) // Seems to cause a revert above this when calculating the tick
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Perform the call
        _onCreate();

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(_baseToken.totalSupply(), _LOT_CAPACITY, "circulating supply");

        // SqrtPriceX96 = sqrt(1e32 * 2^192 / 1e18)
        //              = 7.9456983992e35
        // Tick = log((7.9456983992e35 / 2^96)^2) / log(1.0001)
        //      = 322,435.7131383481 (rounded down)
        // Price = 1.0001^322435 / (10^(18-18)) = 100,571,288,720,819.0986858653
        int24 fixedPriceTick = 322_378; // Not the exact tick, but close enough

        _assertTicks(fixedPriceTick);
    }

    function test_auctionLowPrice()
        public
        givenFixedPrice(1e6)
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Perform the call
        _onCreate();

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(_baseToken.totalSupply(), _LOT_CAPACITY, "circulating supply");

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        // By default, quote token is token1
        // Fixed price = 1e6
        // SqrtPriceX96 = sqrt(1e6 * 2^192 / 1e18)
        //              = 7.9228162514e22
        // Tick = log((7.9228162514e22 / 2^96)^2) / log(1.0001)
        //      = -276,324.02643908 (rounded down)
        // Price = 1.0001^-276,324.02643908 / (10^(18-18)) = 9.9999999999e-13
        int24 fixedPriceTick = -276_325;

        _assertTicks(fixedPriceTick);
    }

    function test_narrowAnchorTickWidth()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(1)
        givenPoolPercent(100e2) // For the solvency check
    {
        // Perform the call
        _onCreate();

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();

        _assertTicks(fixedPriceTick);
    }

    function test_baseTokenAddressHigher_reverts()
        public
        givenBaseTokenAddressHigher
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_BPOOLInvalidAddress.selector);
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_baseTokenDecimalsHigher()
        public
        givenBaseTokenDecimals(19)
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Perform the call
        _onCreate();

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(
            _baseToken.totalSupply(), _scaleBaseTokenAmount(_LOT_CAPACITY), "circulating supply"
        );

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();

        _assertTicks(fixedPriceTick);
    }

    function test_baseTokenDecimalsLower()
        public
        givenBaseTokenDecimals(17)
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Perform the call
        _onCreate();

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(
            _baseToken.totalSupply(), _scaleBaseTokenAmount(_LOT_CAPACITY), "circulating supply"
        );

        // The pool should be initialised with the tick equivalent to the auction's fixed price
        int24 fixedPriceTick = _getFixedPriceTick();

        _assertTicks(fixedPriceTick);
    }

    function test_activeTickRounded()
        public
        givenBPoolFeeTier(10_000)
        givenFixedPrice(1e18)
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        // Perform the call
        _onCreate();

        // Check that the callback owner is correct
        assertEq(_dtl.owner(), _OWNER, "owner");

        // Assert base token balances
        _assertBaseTokenBalances();

        // Lot ID is set
        assertEq(_dtl.lotId(), _lotId, "lot ID");

        // Check circulating supply
        assertEq(_baseToken.totalSupply(), _LOT_CAPACITY, "circulating supply");

        int24 fixedPriceTick = 0;

        _assertTicks(fixedPriceTick);
    }

    function test_anchorRange_overflow_reverts()
        public
        givenPoolInitialTick(TickMath.MAX_TICK - 1) // This will result in the upper tick of the anchor range to be above the MAX_TICK, which should cause a revert
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(1)
    {
        // Expect a revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_Params_RangeOutOfBounds.selector);
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_anchorRange_underflow_reverts()
        public
        givenPoolInitialTick(TickMath.MIN_TICK + 1) // This will result in the lower tick of the anchor range to be below the MIN_TICK, which should cause a revert
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(1)
    {
        // Expect a revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_Params_RangeOutOfBounds.selector);
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    function test_discoveryRange_overflow_reverts()
        public
        givenPoolInitialTick(TickMath.MAX_TICK - _tickSpacing + 1) // This will result in the upper tick of the discovery range to be above the MAX_TICK, which should cause a revert
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(1)
    {
        // Expect a revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_Params_RangeOutOfBounds.selector);
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }

    // There are a few test scenarios that can't be tested:
    // - The upper tick of the floor range is above the MAX_TICK: not possible, since that would require the pool to be initialised with a tick above the MAX_TICK
    // - The lower tick of the discovery range is below the MIN_TICK: not possible, since that would require the pool to be initialised with a tick below the MIN_TICK

    function test_floorRange_underflow_reverts()
        public
        givenPoolInitialTick(TickMath.MIN_TICK) // This will result in the lower tick of the floor range to be below the MIN_TICK, which should cause a revert
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(1)
    {
        // Expect a revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_Params_RangeOutOfBounds.selector);
        vm.expectRevert(err);

        // Perform the call
        _onCreate();
    }
}
