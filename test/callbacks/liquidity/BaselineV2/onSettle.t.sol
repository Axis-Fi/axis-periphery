// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from "./BaselineAxisLaunchTest.sol";

import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {BaselineAxisLaunch} from
    "../../../../src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {Range} from "@baseline/modules/BPOOL.v1.sol";
import {FixedPointMathLib} from "@solmate-6.7.0/utils/FixedPointMathLib.sol";
import {IUniswapV3Pool} from
    "@uniswap-v3-core-1.0.1-solc-0.8-simulate/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap-v3-periphery-1.4.2-solc-0.8/libraries/LiquidityAmounts.sol";
import {PoolAddress} from "@uniswap-v3-periphery-1.4.2-solc-0.8/libraries/PoolAddress.sol";

import {console2} from "@forge-std-1.9.1/console2.sol";

contract BaselineOnSettleTest is BaselineAxisLaunchTest {
    using FixedPointMathLib for uint256;

    // ============ Modifiers ============ //

    // ============ Assertions ============ //

    function _assertQuoteTokenBalances() internal view {
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "quote token: callback");
        assertEq(_quoteToken.balanceOf(address(_quoteToken)), 0, "quote token: contract");
        uint256 poolProceeds = _PROCEEDS_AMOUNT * _createData.poolPercent / 100e2;
        assertEq(
            _quoteToken.balanceOf(address(_baseToken.pool())), poolProceeds, "quote token: pool"
        );
        assertEq(
            _quoteToken.balanceOf(_SELLER), _PROCEEDS_AMOUNT - poolProceeds, "quote token: seller"
        );
    }

    function _assertBaseTokenBalances(uint256 curatorFee_) internal view {
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token: callback");
        assertEq(_baseToken.balanceOf(address(_baseToken)), 0, "base token: contract");

        uint256 totalSupply = _baseToken.totalSupply();
        console2.log("totalSupply", totalSupply);

        // No payout distributed to "bidders", so don't account for it here
        uint256 spotSupply = _LOT_CAPACITY - _REFUND_AMOUNT;
        console2.log("spotSupply", spotSupply);

        uint256 poolSupply = totalSupply - spotSupply - curatorFee_;
        assertEq(_baseToken.balanceOf(address(_baseToken.pool())), poolSupply, "base token: pool");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller");
    }

    function _assertCirculatingSupply(uint256 curatorFee_) internal view {
        uint256 totalSupply = _baseToken.totalSupply();

        assertApproxEqAbs(
            totalSupply - _baseToken.getPosition(Range.FLOOR).bAssets
                - _baseToken.getPosition(Range.ANCHOR).bAssets
                - _baseToken.getPosition(Range.DISCOVERY).bAssets - _creditModule.totalCreditIssued(), // totalCreditIssued would affect supply, totalCollateralized will not
            _LOT_CAPACITY - _REFUND_AMOUNT + curatorFee_,
            2, // There is a difference (rounding error?) of 2
            "circulating supply"
        );
    }

    function _assertAuctionComplete() internal view {
        assertEq(_dtl.auctionComplete(), true, "auction completed");
    }

    function _assertPoolReserves() internal view {
        uint256 poolProceeds = _PROCEEDS_AMOUNT * _createData.poolPercent / 100e2;
        uint256 floorProceeds = poolProceeds * _createData.floorReservesPercent / 100e2;
        assertApproxEqAbs(
            _getRangeReserves(Range.FLOOR),
            floorProceeds,
            1, // There is a difference (rounding error?) of 1
            "reserves: floor"
        );
        assertApproxEqAbs(
            _getRangeReserves(Range.ANCHOR),
            poolProceeds - floorProceeds,
            1, // There is a difference (rounding error?) of 1
            "reserves: anchor"
        );
        assertEq(_getRangeReserves(Range.DISCOVERY), 0, "reserves: discovery");

        // BAssets deployed into the pool
        assertEq(_getRangeBAssets(Range.FLOOR), 0, "bAssets: floor");
        assertEq(_getRangeBAssets(Range.ANCHOR), 0, "bAssets: anchor");
        assertGt(_getRangeBAssets(Range.DISCOVERY), 0, "bAssets: discovery");
    }

    // ============ Tests ============ //

    // [X] when the lot has not been registered
    //  [X] it reverts
    // [X] when the caller is not the auction house
    //  [X] it reverts
    // [X] when the lot has already been settled
    //  [X] it reverts
    // [X] when the lot has already been cancelled
    //  [X] it reverts
    // [X] when insufficient proceeds are sent to the callback
    //  [X] it reverts
    // [X] when insufficient refund is sent to the callback
    //  [X] it reverts
    // [ ] given there is liquidity in the pool at a higher price
    //  [ ] it adjusts the pool price
    // [ ] given there is liquidity in the pool at a lower price
    //  [ ] it adjusts the pool price
    // [X] when the percent in floor reserves changes
    //  [X] it adds reserves to the floor and anchor ranges in the correct proportions
    // [X] given a curator fee has been paid
    //  [X] the solvency check passes
    // [X] given there are credit account allocations
    //  [X] it includes the allocations in the solvency check
    // [X] given the allocation of proceeds to the pool is not 100%
    //  [X] it allocates the proceeds correctly
    // [X] given the anchor range width is fuzzed
    //  [X] it allocates the proceeds correctly
    // [X] given the active tick is fuzzed
    //  [X] it allocates the proceeds correctly
    // [X] it burns refunded base tokens, updates the circulating supply, marks the auction as completed and deploys the reserves into the Baseline pool

    function test_lotNotRegistered_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenAddressHasBaseTokenBalance(_dtlAddress, _REFUND_AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the callback
        _onSettle();
    }

    function test_notAuctionHouse_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenAddressHasBaseTokenBalance(_dtlAddress, _LOT_CAPACITY)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Perform callback
        _dtl.onSettle(
            _lotId, _PROCEEDS_AMOUNT, _scaleBaseTokenAmount(_REFUND_AMOUNT), abi.encode("")
        );
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
        // Perform callback
        _onSettle();

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaselineAxisLaunch.Callback_AlreadyComplete.selector);
        vm.expectRevert(err);

        // Perform callback again
        _onSettle();
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
        _onSettle();
    }

    function test_insufficientProceeds_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasBaseTokenBalance(_dtlAddress, _LOT_CAPACITY)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaselineAxisLaunch.Callback_MissingFunds.selector);
        vm.expectRevert(err);

        // Perform callback
        _onSettle();
    }

    function test_insufficientRefund_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaselineAxisLaunch.Callback_MissingFunds.selector);
        vm.expectRevert(err);

        // Perform callback
        _onSettle();
    }

    function test_success()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();

        // Transfer lock should be disabled
        assertEq(_baseToken.locked(), false, "transfer lock");
    }

    function test_curatorFee_low()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenFloorReservesPercent(30e2) // For the solvency check
        givenPoolPercent(90e2) // For the solvency check
    {
        uint24 curatorFeePercent = 1e2;
        _setCuratorFeePercent(curatorFeePercent);

        // Perform the onCreate callback
        _onCreate();

        // Perform the onCurate callback
        _onCurate(_curatorFee);

        // Mint tokens
        _quoteToken.mint(_dtlAddress, _PROCEEDS_AMOUNT);
        _transferBaseTokenRefund(_REFUND_AMOUNT);

        uint256 refundedCuratorFee = _REFUND_AMOUNT * _curatorFee / _LOT_CAPACITY;
        _transferBaseTokenRefund(refundedCuratorFee);

        // Perform the onSettle callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(_curatorFee - refundedCuratorFee);
        _assertCirculatingSupply(_curatorFee - refundedCuratorFee);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_curatorFee_middle()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenFloorReservesPercent(60e2) // For the solvency check
        givenPoolPercent(90e2) // For the solvency check
    {
        uint24 curatorFeePercent = 5e2;
        _setCuratorFeePercent(curatorFeePercent);

        // Perform the onCreate callback
        _onCreate();

        // Perform the onCurate callback
        _onCurate(_curatorFee);

        // Mint tokens
        _quoteToken.mint(_dtlAddress, _PROCEEDS_AMOUNT);
        _transferBaseTokenRefund(_REFUND_AMOUNT);

        uint256 refundedCuratorFee = _REFUND_AMOUNT * _curatorFee / _LOT_CAPACITY;
        _transferBaseTokenRefund(refundedCuratorFee);

        // Perform the onSettle callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(_curatorFee - refundedCuratorFee);
        _assertCirculatingSupply(_curatorFee - refundedCuratorFee);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_curatorFee_high()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenFloorReservesPercent(20e2) // For the solvency check
        givenPoolPercent(99e2) // For the solvency check
    {
        uint24 curatorFeePercent = 10e2;
        _setCuratorFeePercent(curatorFeePercent);

        // Perform the onCreate callback
        _onCreate();

        // Perform the onCurate callback
        _onCurate(_curatorFee);

        // Mint tokens
        _quoteToken.mint(_dtlAddress, _PROCEEDS_AMOUNT);
        _transferBaseTokenRefund(_REFUND_AMOUNT);

        uint256 refundedCuratorFee = _REFUND_AMOUNT * _curatorFee / _LOT_CAPACITY;
        _transferBaseTokenRefund(refundedCuratorFee);

        // Perform the onSettle callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(_curatorFee - refundedCuratorFee);
        _assertCirculatingSupply(_curatorFee - refundedCuratorFee);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_givenCreditAllocations_low()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenCollateralized(1e18)
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_givenCreditAllocations_middle()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenCollateralized(10e18)
        givenAnchorTickWidth(36) // For the solvency check
        givenFloorReservesPercent(94e2) // For the solvency check
        givenPoolPercent(100e2) // For the solvency check
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_givenCreditAllocations_high()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenCollateralized(20e18)
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_floorReservesPercent_lowPercent()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenPoolPercent(91e2) // For the solvency check
        givenFloorReservesPercent(0)
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_floorReservesPercent_highPercent()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenPoolPercent(82e2) // For the solvency check
        givenFloorReservesPercent(99e2)
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_floorReservesPercent_middlePercent()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenFloorReservesPercent(50e2)
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_poolPercent_lowPercent()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenPoolPercent(10e2)
        givenFloorRangeGap(137) // For the solvency check
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_poolPercent_middlePercent()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenPoolPercent(50e2)
        givenFloorRangeGap(44) // For the solvency check
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_poolPercent_highPercent()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenPoolPercent(90e2)
        givenFloorReservesPercent(10e2) // For the solvency check
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_anchorTickWidth_low()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(10)
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_anchorTickWidth_middle()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(30)
        givenPoolPercent(63e2) // For the solvency check
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_anchorTickWidth_high()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(50)
        givenFloorReservesPercent(0e2) // For the solvency check
        givenPoolPercent(61e2) // For the solvency check
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function uniswapV3MintCallback(uint256, uint256 amount1Owed, bytes calldata) external {
        console2.log("mint callback", amount1Owed);

        // Transfer the quote tokens
        _quoteToken.mint(msg.sender, amount1Owed);
    }

    struct MintCallbackData {
        PoolAddress.PoolKey poolKey;
        address payer;
    }

    function _mintPosition(
        uint256 quoteTokenAmount_,
        int24 tickLower_,
        int24 tickUpper_
    ) internal {
        // Using PoC: https://github.com/GuardianAudits/axis-1/pull/4/files
        // Not currently working

        IUniswapV3Pool pool = _baseToken.pool();
        // uint128 liquidity;
        // {
        //     (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        //     console2.log("sqrtPriceX96", sqrtPriceX96);
        //     uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower_);
        //     console2.log("sqrtRatioAX96", sqrtRatioAX96);
        //     uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper_);
        //     console2.log("sqrtRatioBX96", sqrtRatioBX96);

        //     liquidity = LiquidityAmounts.getLiquidityForAmounts(
        //         sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, 1, quoteTokenAmount_
        //     );
        //     console2.log("liquidity", liquidity);
        // }

        // PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
        //     token0: address(_baseToken),
        //     token1: address(_quoteToken),
        //     fee: _feeTier
        // });

        // This encounters an EVM revert with no error data
        (uint256 amount0, uint256 amount1) =
            pool.mint(address(this), tickLower_, tickUpper_, 1e18, "");
        console2.log("amount0", amount0);
        console2.log("amount1", amount1);
    }

    function test_poolPriceHigher(uint256 quoteTokenAmount_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Provide reserve tokens to the pool at a higher price
        _mintPosition(quoteTokenAmount_, _poolInitialTick + 1, _poolInitialTick + 2);

        // Perform callback
        _onSettle();

        // TODO supply and quote token balances will be different

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_poolPriceLower(uint256 quoteTokenAmount_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Provide reserve tokens to the pool at a lower price
        _mintPosition(quoteTokenAmount_, -60_000 - 60, -60_000);

        // Perform callback
        _onSettle();

        // TODO supply and quote token balances will be different

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }
}
