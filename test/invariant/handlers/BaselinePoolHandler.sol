// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BeforeAfter} from "../helpers/BeforeAfter.sol";
import {Assertions} from "../helpers/Assertions.sol";

import {IUniswapV3Pool} from
    "../../../lib/baseline-v2/lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "../modules/uniswapv3-periphery/interfaces/ISwapRouter.sol";

import {MockERC20} from "@solmate-6.8.0/test/utils/mocks/MockERC20.sol";

abstract contract BaselinePoolHandler is BeforeAfter, Assertions {
    function BaselinePoolHandler_donate(uint256 tokenIndexSeed, uint256 amount) public {
        address _token = tokenIndexSeed % 2 == 0 ? address(_quoteToken) : address(_baselineToken);

        MockERC20(_token).mint(address(this), amount);
        MockERC20(_token).transfer(address(_baselineToken), amount);
    }

    function BaselinePoolHandler_swapToken0(uint256 recipientIndexSeed, uint256 amountIn) public {
        address recipient = randomAddress(recipientIndexSeed);
        if (_quoteToken.balanceOf(recipient) < 1e14) return;
        amountIn = bound(amountIn, 1e14, _quoteToken.balanceOf(recipient));

        (address token0, address token1) = address(_baselineToken) < address(_quoteToken)
            ? (address(_baselineToken), address(_quoteToken))
            : (address(_quoteToken), address(_baselineToken));

        IUniswapV3Pool pool = IUniswapV3Pool(address(_baselineToken.pool()));
        if (address(pool) == address(0)) return;

        vm.prank(recipient);
        _quoteToken.approve(address(_v3SwapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(_quoteToken),
            tokenOut: address(_baselineToken),
            fee: 500,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        vm.prank(recipient);
        try _v3SwapRouter.exactInputSingle(params) {} catch {}
    }

    function BaselinePoolHandler_swapToken1(uint256 recipientIndexSeed, uint256 amountIn) public {
        address recipient = randomAddress(recipientIndexSeed);
        if (_baselineToken.balanceOf(recipient) < 1e14) return;
        amountIn = bound(amountIn, 1e14, _baselineToken.balanceOf(recipient));

        (address token0, address token1) = address(_baselineToken) < address(_quoteToken)
            ? (address(_baselineToken), address(_quoteToken))
            : (address(_quoteToken), address(_baselineToken));

        IUniswapV3Pool pool = IUniswapV3Pool(address(_baselineToken.pool()));
        if (address(pool) == address(0)) return;

        vm.prank(recipient);
        _baselineToken.approve(address(_v3SwapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(_baselineToken),
            tokenOut: address(_quoteToken),
            fee: 500,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        vm.prank(recipient);
        try _v3SwapRouter.exactInputSingle(params) {} catch {}
    }
}
