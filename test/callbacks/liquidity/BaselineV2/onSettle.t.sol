// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from "./BaselineAxisLaunchTest.sol";

import {BaseCallback} from "@axis-core-1.0.4/bases/BaseCallback.sol";
import {BaselineAxisLaunch} from
    "../../../../src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {Range} from "@baseline/modules/BPOOL.v1.sol";
import {FixedPointMathLib} from "@solmate-6.8.0/utils/FixedPointMathLib.sol";
import {IUniswapV3Pool} from
    "@uniswap-v3-core-1.0.1-solc-0.8-simulate/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";

import {console2} from "@forge-std-1.9.1/console2.sol";

contract BaselineOnSettleTest is BaselineAxisLaunchTest {
    using FixedPointMathLib for uint256;

    uint256 internal _additionalQuoteTokensMinted;

    // ============ Modifiers ============ //

    modifier givenFullCapacity() {
        _proceeds = 30e18;
        _refund = 0;
        _;
    }

    // ============ Assertions ============ //

    function _assertQuoteTokenBalances() internal view {
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "quote token: callback");
        assertEq(_quoteToken.balanceOf(address(_quoteToken)), 0, "quote token: contract");

        uint256 proceedsAfterFees = _proceeds - _protocolFee - _referrerFee;
        uint256 poolProceeds = proceedsAfterFees * _createData.poolPercent / 100e2;
        assertEq(
            _quoteToken.balanceOf(address(_baseToken.pool())),
            poolProceeds + _additionalQuoteTokensMinted,
            "quote token: pool"
        );
        assertEq(
            _quoteToken.balanceOf(_SELLER), proceedsAfterFees - poolProceeds, "quote token: seller"
        );
    }

    function _assertBaseTokenBalances(uint256 curatorFee_) internal view {
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token: callback");
        assertEq(_baseToken.balanceOf(address(_baseToken)), 0, "base token: contract");

        uint256 totalSupply = _baseToken.totalSupply();
        console2.log("totalSupply", totalSupply);

        // No payout distributed to "bidders", so don't account for it here
        uint256 spotSupply = _LOT_CAPACITY - _refund;
        console2.log("spotSupply", spotSupply);

        uint256 poolSupply =
            totalSupply - spotSupply - curatorFee_ - _creditModule.totalCollateralized();
        assertEq(_baseToken.balanceOf(address(_baseToken.pool())), poolSupply, "base token: pool");
        assertEq(_baseToken.balanceOf(_SELLER), 0, "base token: seller");
    }

    function _assertCirculatingSupply(uint256 curatorFee_) internal view {
        uint256 totalSupply = _baseToken.totalSupply();

        assertApproxEqAbs(
            totalSupply - _baseToken.getPosition(Range.FLOOR).bAssets
                - _baseToken.getPosition(Range.ANCHOR).bAssets
                - _baseToken.getPosition(Range.DISCOVERY).bAssets,
            _LOT_CAPACITY - _refund + curatorFee_ + _creditModule.totalCollateralized(),
            2, // There is a difference (rounding error?) of 2
            "circulating supply"
        );
    }

    function _assertAuctionComplete() internal view {
        assertEq(_dtl.auctionComplete(), true, "auction completed");
    }

    function _assertPoolReserves() internal view {
        uint256 poolProceeds =
            (_proceeds - _protocolFee - _referrerFee) * _createData.poolPercent / 100e2;
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
    // [X] given the onSettle callback has already been called
    //  [X] when onSettle is called
    //   [X] it reverts
    //  [X] when onCancel is called
    //   [X] it reverts
    //  [X] when onCurate is called
    //   [X] it reverts
    //  [X] when onCreate is called
    //   [X] it reverts
    // [X] when the lot has already been cancelled
    //  [X] it reverts
    // [X] when insufficient proceeds are sent to the callback
    //  [X] it reverts
    // [X] when insufficient refund is sent to the callback
    //  [X] it reverts
    // [X] given there is liquidity in the pool at a higher tick
    //  [X] it adjusts the pool price
    // [X] given there is liquidity in the pool at a lower tick
    //  [X] it adjusts the pool price
    // [X] when the percent in floor reserves changes
    //  [X] it adds reserves to the floor and anchor ranges in the correct proportions
    // [X] given a curator fee has been paid
    //  [X] the solvency check passes
    // [X] given there are credit account allocations
    //  [X] it includes the allocations in the solvency check
    // [ ] given there is loop vault debt
    //  [ ] it includes the debt in the solvency check
    // [X] given the allocation of proceeds to the pool is not 100%
    //  [X] it allocates the proceeds correctly
    // [X] given the anchor range width is fuzzed
    //  [X] it allocates the proceeds correctly
    // [X] given the active tick is fuzzed
    //  [X] it allocates the proceeds correctly
    // [X] given the protocol fee is set
    //  [X] it correctly performs the solvency check
    // [X] given the referrer fee is set
    //  [X] it correctly performs the solvency check
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

    function test_auctionCompleted_onCreate_reverts()
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
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        // Perform callback again
        _onCreate();
    }

    function test_auctionCompleted_onCurate_reverts()
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
        _onCurate(0);
    }

    function test_auctionCompleted_onCancel_reverts()
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
        _onCancel();
    }

    function test_auctionCompleted_onSettle_reverts()
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

        // Transfer lock should be enabled
        assertEq(_baseToken.locked(), true, "transfer lock");
    }

    function test_curatorFee_low()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenFloorReservesPercent(30e2) // For the solvency check
        givenPoolPercent(90e2) // For the solvency check
    {
        uint48 curatorFeePercent = 1e2;
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
        uint48 curatorFeePercent = 5e2;
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
        uint48 curatorFeePercent = 10e2;
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
        givenPoolPercent(92e2) // For the solvency check
        givenCollateralized(_BORROWER, 1e18)
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenBaseTokenRefundIsTransferred(_refund)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_givenCreditAllocations_low_givenFullCapacity()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenPoolPercent(92e2) // For the solvency check
        givenCollateralized(_BORROWER, 1e18)
        givenOnCreate
        givenFullCapacity
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenBaseTokenRefundIsTransferred(_refund)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_givenCreditAllocations_middle_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(20) // For the solvency check
        givenFloorReservesPercent(25e2) // For the solvency check
        givenPoolPercent(99e2) // For the solvency check
        givenCollateralized(_BORROWER, 5e18)
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenBaseTokenRefundIsTransferred(_refund)
    {
        // Expect revert
        // The solvency check fails due to the refund
        bytes memory err = abi.encodeWithSelector(
            BaselineAxisLaunch.Callback_InvalidCapacityRatio.selector, 979_448_372_805_591_283
        );

        // Perform callback
        _onSettle(err);
    }

    function test_givenCreditAllocations_middle_givenFullCapacity()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(20) // For the solvency check
        givenFloorReservesPercent(25e2) // For the solvency check
        givenPoolPercent(99e2) // For the solvency check
        givenCollateralized(_BORROWER, 5e18)
        givenOnCreate
        givenFullCapacity
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenBaseTokenRefundIsTransferred(_refund)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_givenCreditAllocations_high_reverts()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(31) // For the solvency check
        givenCollateralized(_BORROWER, 10e18)
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenBaseTokenRefundIsTransferred(_refund)
    {
        // Expect revert
        // The solvency check fails due to the refund
        bytes memory err = abi.encodeWithSelector(
            BaselineAxisLaunch.Callback_InvalidCapacityRatio.selector, 972_981_853_960_360_268
        );

        // Perform callback
        _onSettle(err);
    }

    function test_givenCreditAllocations_high_givenFullCapacity()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenAnchorTickWidth(31) // For the solvency check
        givenCollateralized(_BORROWER, 10e18)
        givenOnCreate
        givenFullCapacity
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenBaseTokenRefundIsTransferred(_refund)
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
        givenFloorReservesPercent(10e2)
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
        givenPoolPercent(83e2) // For the solvency check
        givenFloorReservesPercent(90e2)
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
        givenFloorReservesPercent(10e2) // For the solvency check
        givenPoolPercent(58e2) // For the solvency check
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
        console2.log("Minting additional quote tokens", amount1Owed);
        _additionalQuoteTokensMinted += amount1Owed;

        // Transfer the quote tokens
        _quoteToken.mint(msg.sender, amount1Owed);
    }

    function _mintPosition(int24 tickLower_, int24 tickUpper_) internal {
        // Using PoC: https://github.com/GuardianAudits/axis-1/pull/4/files
        IUniswapV3Pool pool = _baseToken.pool();

        pool.mint(address(this), tickLower_, tickUpper_, 1e18, "");
    }

    function uniswapV3SwapCallback(int256, int256, bytes memory) external pure {
        return;
    }

    function _swap(uint160 sqrtPrice_) internal {
        IUniswapV3Pool pool = _baseToken.pool();

        pool.swap(address(this), true, 1, sqrtPrice_, "");
    }

    function test_existingReservesAtHigherPoolTick()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Assert the pool price
        int24 poolTick;
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        assertEq(poolTick, 10_986, "pool tick after mint"); // Original active tick

        // Swap at a tick higher than the anchor range
        IUniswapV3Pool pool = _baseToken.pool();
        pool.swap(address(this), false, 1, TickMath.getSqrtRatioAtTick(60_000), "");

        // Assert that the pool tick has moved higher
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        assertEq(poolTick, 60_000, "pool tick after swap");

        // Provide reserve tokens to the pool at a tick higher than the anchor range and lower than the new active tick
        _mintPosition(12_000, 12_000 + _tickSpacing);

        // Perform callback
        _onSettle();

        // Assert that the pool tick has corrected
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        assertEq(poolTick, 11_000, "pool tick after settlement"); // Ends up rounded to the tick spacing

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        // _assertCirculatingSupply(0); // Difficult to calculate the additional base tokens minted
        _assertAuctionComplete();
        // _assertPoolReserves(); // Difficult to calculate the additional quote and base tokens into ranges
    }

    function test_existingReservesAtHigherPoolTick_noLiquidity()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Assert the pool price
        int24 poolTick;
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        assertEq(poolTick, 10_986, "pool tick after mint"); // Original active tick

        // Swap at a tick higher than the anchor range
        IUniswapV3Pool pool = _baseToken.pool();
        pool.swap(address(this), false, 1, TickMath.getSqrtRatioAtTick(60_000), "");

        // Assert that the pool tick has moved higher
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        assertEq(poolTick, 60_000, "pool tick after swap");

        // Do not mint any liquidity above the anchor range

        // Perform callback
        _onSettle();

        // Assert that the pool tick has corrected
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        assertEq(poolTick, 11_000, "pool tick after settlement"); // Ends up rounded to the tick spacing

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_existingReservesAtLowerPoolTick()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Provide reserve tokens to the pool at a lower tick
        _mintPosition(-60_000 - _tickSpacing, -60_000);

        // Assert the pool price
        int24 poolTick;
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        assertEq(poolTick, 10_986, "pool tick after mint"); // Original active tick

        // Swap
        _swap(TickMath.getSqrtRatioAtTick(-60_000));

        // Assert that the pool price has moved lower
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        assertEq(poolTick, -60_001, "pool tick after swap");

        // Perform callback
        _onSettle();

        // Assert that the pool tick has corrected
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        assertEq(poolTick, 11_000, "pool tick after settlement"); // Ends up rounded to the tick spacing

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_existingReservesAtLowerPoolTick_noLiquidity()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // Don't mint any liquidity

        // Assert the pool price
        int24 poolTick;
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        assertEq(poolTick, 10_986, "pool tick after mint"); // Original active tick

        // Swap
        _swap(TickMath.getSqrtRatioAtTick(-60_000));

        // Assert that the pool price has moved lower
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        assertEq(poolTick, -60_000, "pool tick after swap");

        // Perform callback
        _onSettle();

        // Assert that the pool tick has corrected
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        assertEq(poolTick, 11_000, "pool tick after settlement"); // Ends up rounded to the tick spacing

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();
    }

    function test_givenProtocolFee()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenProtocolFeePercent(1e2) // 1%
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds - _protocolFee)
        givenBaseTokenRefundIsTransferred(_refund)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();

        // Transfer lock should be enabled
        assertEq(_baseToken.locked(), true, "transfer lock");
    }

    function test_givenReferrerFee()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenReferrerFeePercent(1e2) // 1%
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds - _referrerFee)
        givenBaseTokenRefundIsTransferred(_refund)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();

        // Transfer lock should be enabled
        assertEq(_baseToken.locked(), true, "transfer lock");
    }

    function test_givenProtocolFee_givenReferrerFee()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenProtocolFeePercent(5e1) // 0.5%
        givenReferrerFeePercent(5e1) // 0.5%
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds - _protocolFee - _referrerFee)
        givenBaseTokenRefundIsTransferred(_refund)
    {
        // Perform callback
        _onSettle();

        _assertQuoteTokenBalances();
        _assertBaseTokenBalances(0);
        _assertCirculatingSupply(0);
        _assertAuctionComplete();
        _assertPoolReserves();

        // Transfer lock should be enabled
        assertEq(_baseToken.locked(), true, "transfer lock");
    }
}
