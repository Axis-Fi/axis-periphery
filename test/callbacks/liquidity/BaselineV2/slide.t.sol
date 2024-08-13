// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {BaselineAxisLaunchTest} from "./BaselineAxisLaunchTest.sol";

import {Range} from "@baseline/modules/BPOOL.v1.sol";
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";

import {console2} from "@forge-std-1.9.1/console2.sol";

contract BaselineOnSettleSlideTest is BaselineAxisLaunchTest {
    function uniswapV3SwapCallback(
        int256 amount0Delta_,
        int256 amount1Delta_,
        bytes memory
    ) external {
        console2.log("amount0Delta", amount0Delta_);
        console2.log("amount1Delta", amount1Delta_);

        if (amount0Delta_ > 0) {
            _baseToken.transfer(msg.sender, uint256(amount0Delta_));
        }

        if (amount1Delta_ > 0) {
            _quoteToken.transfer(msg.sender, uint256(amount1Delta_));
        }

        return;
    }

    function test_floorReservesPercent_lowPercent_slide()
        public
        givenFixedPrice(1e18)
        givenAnchorUpperTick(200)
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenPoolPercent(92e2) // For the solvency check
        givenFloorReservesPercent(10e2)
        givenAnchorTickWidth(10)
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, 8e18)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
        _proceeds = 8e18;
        _refund = _REFUND_AMOUNT;

        // Perform callback
        _onSettle();

        // Report the range ticks
        (int24 floorL, int24 floorU) = _baseToken.getTicks(Range.FLOOR);
        (int24 anchorL, int24 anchorU) = _baseToken.getTicks(Range.ANCHOR);
        (int24 discoveryL, int24 discoveryU) = _baseToken.getTicks(Range.DISCOVERY);
        console2.log("floor lower", floorL);
        console2.log("floor upper", floorU);
        console2.log("anchor lower", anchorL);
        console2.log("anchor upper", anchorU);
        console2.log("discovery lower", discoveryL);
        console2.log("discovery upper", discoveryU);

        // Check the tick
        (, int24 poolTick,,,,,) = _baseToken.pool().slot0();
        console2.log("pool tick after settlement", poolTick);

        // Transfer base tokens from AuctionHouse to here (so we don't mess with solvency)
        // This represents ALL circulating base tokens
        vm.prank(_AUCTION_HOUSE);
        _baseToken.transfer(address(this), 8e18);

        // Swap base tokens to reduce the pool price
        _baseToken.pool().swap(_SELLER, true, 8e18, TickMath.MIN_SQRT_RATIO + 1, "");

        // Check the tick
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        console2.log("pool tick after swap", poolTick);

        // Attempt to slide
        _marketMaking.slide();

        // Check the tick
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        console2.log("pool tick after slide", poolTick);

        // Report the range ticks
        (floorL, floorU) = _baseToken.getTicks(Range.FLOOR);
        (anchorL, anchorU) = _baseToken.getTicks(Range.ANCHOR);
        (discoveryL, discoveryU) = _baseToken.getTicks(Range.DISCOVERY);
        console2.log("floor lower", floorL);
        console2.log("floor upper", floorU);
        console2.log("anchor lower", anchorL);
        console2.log("anchor upper", anchorU);
        console2.log("discovery lower", discoveryL);
        console2.log("discovery upper", discoveryU);
    }
}
