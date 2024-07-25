// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from "./BaselineAxisLaunchTest.sol";

import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {BaselineAxisLaunch} from
    "../../../../src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {Range, Position} from "@baseline/modules/BPOOL.v1.sol";
import {FixedPointMathLib} from "@solmate-6.7.0/utils/FixedPointMathLib.sol";

contract BaselineOnSettleTest is BaselineAxisLaunchTest {
    using FixedPointMathLib for uint256;

    // ============ Modifiers ============ //

    // ============ Assertions ============ //

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
    // [X] when the percent in floor reserves changes
    //  [X] it adds reserves to the floor and anchor ranges in the correct proportions
    // [X] given a curator fee has been paid
    //  [X] the solvency check passes
    // [X] given there are credit account allocations
    //  [X] it includes the allocations in the solvency check
    // [X] it burns refunded base tokens, updates the circulating supply, marks the auction as completed and deploys the reserves into the Baseline pool

    // TODO poolPercent fuzzing
    // TODO anchor width fuzzing
    // TODO discovery width fuzzing
    // TODO active tick fuzzing

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

        // Assert quote token balances
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "quote token: callback");
        assertEq(_quoteToken.balanceOf(address(_quoteToken)), 0, "quote token: contract");
        assertEq(
            _quoteToken.balanceOf(address(_baseToken.pool())), _PROCEEDS_AMOUNT, "quote token: pool"
        );

        // Assert base token balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token: callback");
        assertEq(_baseToken.balanceOf(address(_baseToken)), 0, "base token: contract");
        uint256 totalSupply = _baseToken.totalSupply();
        uint256 poolSupply = totalSupply - _LOT_CAPACITY + _REFUND_AMOUNT;
        assertEq(_baseToken.balanceOf(address(_baseToken.pool())), poolSupply, "base token: pool");

        // Circulating supply
        assertApproxEqAbs(
            totalSupply - _baseToken.getPosition(Range.FLOOR).bAssets
                - _baseToken.getPosition(Range.ANCHOR).bAssets
                - _baseToken.getPosition(Range.DISCOVERY).bAssets - _creditModule.totalCollateralized(),
            _LOT_CAPACITY - _REFUND_AMOUNT,
            2, // There is a difference (rounding error?) of 2
            "circulating supply"
        );

        // Auction marked as complete
        assertEq(_dtl.auctionComplete(), true, "auction completed");

        // Reserves deployed into the pool
        assertApproxEqAbs(
            _getRangeReserves(Range.FLOOR),
            _PROCEEDS_AMOUNT.mulDivDown(_FLOOR_RESERVES_PERCENT, _ONE_HUNDRED_PERCENT),
            1, // There is a difference (rounding error?) of 1
            "reserves: floor"
        );
        assertApproxEqAbs(
            _getRangeReserves(Range.ANCHOR),
            _PROCEEDS_AMOUNT.mulDivDown(
                _ONE_HUNDRED_PERCENT - _FLOOR_RESERVES_PERCENT, _ONE_HUNDRED_PERCENT
            ),
            1, // There is a difference (rounding error?) of 1
            "reserves: anchor"
        );
        assertEq(_getRangeReserves(Range.DISCOVERY), 0, "reserves: discovery");

        // BAssets deployed into the pool
        assertEq(_getRangeBAssets(Range.FLOOR), 0, "bAssets: floor");
        assertGt(_getRangeBAssets(Range.ANCHOR), 0, "bAssets: anchor");
        assertGt(_getRangeBAssets(Range.DISCOVERY), 0, "bAssets: discovery");
    }

    function test_curatorFee(uint256 curatorFee_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // This enables a curator fee theoretically up to the total proceeds
        uint256 curatorFee = bound(curatorFee_, 1, (_PROCEEDS_AMOUNT - _REFUND_AMOUNT));

        // Perform the onCurate callback
        _onCurate(curatorFee);

        // Perform the onSettle callback
        _onSettle();

        // Assert quote token balances
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "quote token: callback");
        assertEq(_quoteToken.balanceOf(address(_quoteToken)), 0, "quote token: contract");
        assertEq(
            _quoteToken.balanceOf(address(_baseToken.pool())), _PROCEEDS_AMOUNT, "quote token: pool"
        );

        // Assert base token balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token: callback");
        assertEq(_baseToken.balanceOf(address(_baseToken)), 0, "base token: contract");
        uint256 totalSupply = _baseToken.totalSupply();
        uint256 poolSupply = totalSupply - _LOT_CAPACITY + _REFUND_AMOUNT - curatorFee;
        assertEq(_baseToken.balanceOf(address(_baseToken.pool())), poolSupply, "base token: pool");

        // Circulating supply
        assertApproxEqAbs(
            totalSupply - _baseToken.getPosition(Range.FLOOR).bAssets
                - _baseToken.getPosition(Range.ANCHOR).bAssets
                - _baseToken.getPosition(Range.DISCOVERY).bAssets - _creditModule.totalCreditIssued(), // totalCreditIssued would affect supply, totalCollateralized will not
            _LOT_CAPACITY - _REFUND_AMOUNT + curatorFee,
            2, // There is a difference (rounding error?) of 2
            "circulating supply"
        );
    }

    function test_givenCreditAllocations_fuzz(uint256 creditAllocations_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        // NOTE: somewhere around 88526166011773621485726186888697, this makes the Baseline token insolvent. Should this be accepted as an upper limit with tests? Any further action?
        uint256 creditAllocations = bound(creditAllocations_, 0, type(uint256).max);

        // Allocate credit accounts
        _creditModule.setTotalCollateralized(creditAllocations);

        // Perform callback
        _onSettle();

        // Assert quote token balances
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "quote token: callback");
        assertEq(_quoteToken.balanceOf(address(_quoteToken)), 0, "quote token: contract");
        assertEq(
            _quoteToken.balanceOf(address(_baseToken.pool())), _PROCEEDS_AMOUNT, "quote token: pool"
        );

        // Assert base token balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token: callback");
        assertEq(_baseToken.balanceOf(address(_baseToken)), 0, "base token: contract");
        uint256 totalSupply = _baseToken.totalSupply();
        uint256 poolSupply = totalSupply - _LOT_CAPACITY + _REFUND_AMOUNT;
        assertEq(_baseToken.balanceOf(address(_baseToken.pool())), poolSupply, "base token: pool");

        // Circulating supply
        assertApproxEqAbs(
            totalSupply - _baseToken.getPosition(Range.FLOOR).bAssets
                - _baseToken.getPosition(Range.ANCHOR).bAssets
                - _baseToken.getPosition(Range.DISCOVERY).bAssets - _creditModule.totalCreditIssued(), // totalCreditIssued would affect supply, totalCollateralized will not
            _LOT_CAPACITY - _REFUND_AMOUNT,
            2, // There is a difference (rounding error?) of 2
            "circulating supply"
        );
    }

    function test_floorReservesPercent_zero()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        uint24 floorReservesPercent = 0;

        // Update the callback parameters
        _createData.floorReservesPercent = floorReservesPercent;

        // Call onCreate
        _onCreate();

        // Mint tokens
        _quoteToken.mint(_dtlAddress, _PROCEEDS_AMOUNT);

        // Transfer refund from auction house to the callback
        _transferBaseTokenRefund(_REFUND_AMOUNT);

        // Perform callback
        _onSettle();

        // Assert quote token balances
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "quote token: callback");
        assertEq(_quoteToken.balanceOf(address(_quoteToken)), 0, "quote token: contract");
        assertEq(
            _quoteToken.balanceOf(address(_baseToken.pool())), _PROCEEDS_AMOUNT, "quote token: pool"
        );

        // Assert base token balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token: callback");
        assertEq(_baseToken.balanceOf(address(_baseToken)), 0, "base token: contract");
        uint256 totalSupply = _baseToken.totalSupply();
        uint256 poolSupply = totalSupply - _LOT_CAPACITY + _REFUND_AMOUNT;
        assertEq(_baseToken.balanceOf(address(_baseToken.pool())), poolSupply, "base token: pool");

        // Circulating supply
        assertApproxEqAbs(
            totalSupply - _baseToken.getPosition(Range.FLOOR).bAssets
                - _baseToken.getPosition(Range.ANCHOR).bAssets
                - _baseToken.getPosition(Range.DISCOVERY).bAssets - _creditModule.totalCollateralized(),
            _LOT_CAPACITY - _REFUND_AMOUNT,
            2, // There is a difference (rounding error?) of 2
            "circulating supply"
        );

        // Auction marked as complete
        assertEq(_dtl.auctionComplete(), true, "auction completed");

        // Reserves deployed into the pool
        assertApproxEqAbs(
            _getRangeReserves(Range.FLOOR),
            _PROCEEDS_AMOUNT.mulDivDown(floorReservesPercent, _ONE_HUNDRED_PERCENT),
            1, // There is a difference (rounding error?) of 1
            "reserves: floor"
        );
        assertApproxEqAbs(
            _getRangeReserves(Range.ANCHOR),
            _PROCEEDS_AMOUNT.mulDivDown(
                _ONE_HUNDRED_PERCENT - floorReservesPercent, _ONE_HUNDRED_PERCENT
            ),
            1, // There is a difference (rounding error?) of 1
            "reserves: anchor"
        );
        assertEq(_getRangeReserves(Range.DISCOVERY), 0, "reserves: discovery");

        // BAssets deployed into the pool
        assertEq(_getRangeBAssets(Range.FLOOR), 0, "bAssets: floor");
        assertGt(_getRangeBAssets(Range.ANCHOR), 0, "bAssets: anchor");
        assertGt(_getRangeBAssets(Range.DISCOVERY), 0, "bAssets: discovery");
    }

    function test_floorReservesPercent_ninetyNinePercent()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        uint24 floorReservesPercent = _NINETY_NINE_PERCENT;

        // Update the callback parameters
        _createData.floorReservesPercent = floorReservesPercent;

        // Call onCreate
        _onCreate();

        // Mint tokens
        _quoteToken.mint(_dtlAddress, _PROCEEDS_AMOUNT);

        // Transfer refund from auction house to the callback
        _transferBaseTokenRefund(_REFUND_AMOUNT);

        // Perform callback
        _onSettle();

        // Assert quote token balances
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "quote token: callback");
        assertEq(_quoteToken.balanceOf(address(_quoteToken)), 0, "quote token: contract");
        assertEq(
            _quoteToken.balanceOf(address(_baseToken.pool())), _PROCEEDS_AMOUNT, "quote token: pool"
        );

        // Assert base token balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token: callback");
        assertEq(_baseToken.balanceOf(address(_baseToken)), 0, "base token: contract");
        uint256 totalSupply = _baseToken.totalSupply();
        uint256 poolSupply = totalSupply - _LOT_CAPACITY + _REFUND_AMOUNT;
        assertEq(_baseToken.balanceOf(address(_baseToken.pool())), poolSupply, "base token: pool");

        // Circulating supply
        assertApproxEqAbs(
            totalSupply - _baseToken.getPosition(Range.FLOOR).bAssets
                - _baseToken.getPosition(Range.ANCHOR).bAssets
                - _baseToken.getPosition(Range.DISCOVERY).bAssets - _creditModule.totalCollateralized(),
            _LOT_CAPACITY - _REFUND_AMOUNT,
            2, // There is a difference (rounding error?) of 2
            "circulating supply"
        );

        // Auction marked as complete
        assertEq(_dtl.auctionComplete(), true, "auction completed");

        // Reserves deployed into the pool
        assertApproxEqAbs(
            _getRangeReserves(Range.FLOOR),
            _PROCEEDS_AMOUNT.mulDivDown(floorReservesPercent, _ONE_HUNDRED_PERCENT),
            1, // There is a difference (rounding error?) of 1
            "reserves: floor"
        );
        assertApproxEqAbs(
            _getRangeReserves(Range.ANCHOR),
            _PROCEEDS_AMOUNT.mulDivDown(
                _ONE_HUNDRED_PERCENT - floorReservesPercent, _ONE_HUNDRED_PERCENT
            ),
            1, // There is a difference (rounding error?) of 1
            "reserves: anchor"
        );
        assertEq(_getRangeReserves(Range.DISCOVERY), 0, "reserves: discovery");

        // BAssets deployed into the pool
        assertEq(_getRangeBAssets(Range.FLOOR), 0, "bAssets: floor");
        assertGt(_getRangeBAssets(Range.ANCHOR), 0, "bAssets: anchor");
        assertGt(_getRangeBAssets(Range.DISCOVERY), 0, "bAssets: discovery");
    }

    function test_floorReservesPercent_fuzz(uint24 floorReservesPercent_)
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
    {
        uint24 floorReservesPercent = uint24(bound(floorReservesPercent_, 0, _NINETY_NINE_PERCENT));

        // Update the callback parameters
        _createData.floorReservesPercent = floorReservesPercent;

        // Call onCreate
        _onCreate();

        // Mint tokens
        _quoteToken.mint(_dtlAddress, _PROCEEDS_AMOUNT);

        // Transfer refund from auction house to the callback
        _transferBaseTokenRefund(_REFUND_AMOUNT);

        // Perform callback
        _onSettle();

        // Assert quote token balances
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "quote token: callback");
        assertEq(_quoteToken.balanceOf(address(_quoteToken)), 0, "quote token: contract");
        assertEq(
            _quoteToken.balanceOf(address(_baseToken.pool())), _PROCEEDS_AMOUNT, "quote token: pool"
        );

        // Assert base token balances
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "base token: callback");
        assertEq(_baseToken.balanceOf(address(_baseToken)), 0, "base token: contract");
        uint256 totalSupply = _baseToken.totalSupply();
        uint256 poolSupply = totalSupply - _LOT_CAPACITY + _REFUND_AMOUNT;
        assertEq(_baseToken.balanceOf(address(_baseToken.pool())), poolSupply, "base token: pool");

        // Circulating supply
        assertApproxEqAbs(
            totalSupply - _baseToken.getPosition(Range.FLOOR).bAssets
                - _baseToken.getPosition(Range.ANCHOR).bAssets
                - _baseToken.getPosition(Range.DISCOVERY).bAssets - _creditModule.totalCollateralized(),
            _LOT_CAPACITY - _REFUND_AMOUNT,
            2,
            "circulating supply"
        );

        // Auction marked as complete
        assertEq(_dtl.auctionComplete(), true, "auction completed");

        // Reserves deployed into the pool
        assertApproxEqAbs(
            _getRangeReserves(Range.FLOOR),
            _PROCEEDS_AMOUNT.mulDivDown(floorReservesPercent, _ONE_HUNDRED_PERCENT),
            1,
            "reserves: floor"
        );
        assertApproxEqAbs(
            _getRangeReserves(Range.ANCHOR),
            _PROCEEDS_AMOUNT.mulDivDown(
                _ONE_HUNDRED_PERCENT - floorReservesPercent, _ONE_HUNDRED_PERCENT
            ),
            1,
            "reserves: anchor"
        );
        assertEq(_getRangeReserves(Range.DISCOVERY), 0, "reserves: discovery");

        // BAssets deployed into the pool
        assertEq(_getRangeBAssets(Range.FLOOR), 0, "bAssets: floor");
        assertGt(_getRangeBAssets(Range.ANCHOR), 0, "bAssets: anchor");
        assertGt(_getRangeBAssets(Range.DISCOVERY), 0, "bAssets: discovery");
    }
}
