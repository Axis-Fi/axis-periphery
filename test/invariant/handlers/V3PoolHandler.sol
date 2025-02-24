// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BeforeAfter} from "../helpers/BeforeAfter.sol";
import {Assertions} from "../helpers/Assertions.sol";

import {IUniswapV3Pool} from
    "@uniswap-v3-core-1.0.1-solc-0.8-simulate/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "../modules/uniswapv3-periphery/interfaces/ISwapRouter.sol";
import {MockERC20} from "@solmate-6.8.0/test/utils/mocks/MockERC20.sol";

abstract contract V3PoolHandler is BeforeAfter, Assertions {
    function V3PoolHandler_donate(uint256 tokenIndexSeed, uint256 amount) public {
        address _token = tokenIndexSeed % 2 == 0 ? address(_quoteToken) : address(_baseToken);
        (address token0, address token1) = address(_baseToken) < address(_quoteToken)
            ? (address(_baseToken), address(_quoteToken))
            : (address(_quoteToken), address(_baseToken));
        address pool = _uniV3Factory.getPool(token0, token1, 500);

        amount = bound(amount, 1, 10_000 ether);

        MockERC20(_token).mint(address(this), amount);
        MockERC20(_token).transfer(address(pool), amount);
    }

    function V3PoolHandler_swapToken0(uint256 recipientIndexSeed, uint256 amountIn) public {
        address recipient = randomAddress(recipientIndexSeed);
        if (_quoteToken.balanceOf(recipient) < 1e14) return;
        amountIn = bound(amountIn, 1e14, _quoteToken.balanceOf(recipient));

        (address token0, address token1) = address(_baseToken) < address(_quoteToken)
            ? (address(_baseToken), address(_quoteToken))
            : (address(_quoteToken), address(_baseToken));

        IUniswapV3Pool pool = IUniswapV3Pool(_uniV3Factory.getPool(token0, token1, 500));
        if (address(pool) == address(0)) return;

        vm.prank(recipient);
        _quoteToken.approve(address(_v3SwapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(_quoteToken),
            tokenOut: address(_baseToken),
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

    function V3PoolHandler_swapToken1(uint256 recipientIndexSeed, uint256 amountIn) public {
        address recipient = randomAddress(recipientIndexSeed);
        if (_baseToken.balanceOf(recipient) < 1e14) return;
        amountIn = bound(amountIn, 1e14, _baseToken.balanceOf(recipient));

        (address token0, address token1) = address(_baseToken) < address(_quoteToken)
            ? (address(_baseToken), address(_quoteToken))
            : (address(_quoteToken), address(_baseToken));

        IUniswapV3Pool pool = IUniswapV3Pool(_uniV3Factory.getPool(token0, token1, 500));
        if (address(pool) == address(0)) return;

        vm.prank(recipient);
        _baseToken.approve(address(_v3SwapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(_baseToken),
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
