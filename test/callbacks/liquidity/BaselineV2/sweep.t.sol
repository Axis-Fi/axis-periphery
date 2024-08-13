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

    function test_floorReservesPercent_highPercent_sweep()
        public
        givenBPoolIsCreated
        givenCallbackIsCreated
        givenAuctionIsCreated
        givenPoolPercent(82e2) // For the solvency check
        givenFloorReservesPercent(99e2)
        givenAnchorTickWidth(10)
        givenOnCreate
        givenAddressHasQuoteTokenBalance(_dtlAddress, _PROCEEDS_AMOUNT)
        givenBaseTokenRefundIsTransferred(_REFUND_AMOUNT)
    {
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

        // Mint quote tokens for the swap
        _quoteToken.mint(address(this), 150e18);

        // Swap quote tokens to reduce the pool price
        _baseToken.pool().swap(_SELLER, false, 150e18, TickMath.MAX_SQRT_RATIO - 1, "");

        // Check the tick
        (, poolTick,,,,,) = _baseToken.pool().slot0();
        console2.log("pool tick after swap", poolTick);

        // Attempt to sweep
        assertEq(_marketMaking.canSweep(), true, "canSweep");
        _marketMaking.sweep();

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
