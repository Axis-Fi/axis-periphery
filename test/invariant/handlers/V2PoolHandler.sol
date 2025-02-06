// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BeforeAfter} from "../helpers/BeforeAfter.sol";
import {Assertions} from "../helpers/Assertions.sol";

import {IUniswapV2Pair} from "@uniswap-v2-core-1.0.1/interfaces/IUniswapV2Pair.sol";

import {MockERC20} from "@solmate-6.8.0/test/utils/mocks/MockERC20.sol";

abstract contract V2PoolHandler is BeforeAfter, Assertions {
    function V2PoolHandler_donate(uint256 tokenIndexSeed, uint256 amount) public {
        // address _token = tokenIndexSeed % 2 == 0 ? address(_quoteToken) : address(_baseToken);
        address _token = address(_quoteToken);

        address pairAddress = _uniV2Factory.getPair(address(_baseToken), address(_quoteToken));
        if (pairAddress == address(0)) {
            pairAddress = _uniV2Factory.createPair(address(_baseToken), address(_quoteToken));
        }
        IUniswapV2Pair pool = IUniswapV2Pair(pairAddress);

        amount = bound(amount, 1, 10_000 ether);

        MockERC20(_token).mint(address(this), amount);
        MockERC20(_token).transfer(address(pool), amount);
    }

    function V2PoolHandler_sync() public {
        address pairAddress = _uniV2Factory.getPair(address(_baseToken), address(_quoteToken));
        if (pairAddress == address(0)) return;
        IUniswapV2Pair pool = IUniswapV2Pair(pairAddress);

        pool.sync();
    }

    function V2PoolHandler_skim(uint256 userIndexSeed) public {
        address to = randomAddress(userIndexSeed);
        address pairAddress = _uniV2Factory.getPair(address(_baseToken), address(_quoteToken));
        if (pairAddress == address(0)) return;
        IUniswapV2Pair pool = IUniswapV2Pair(pairAddress);

        pool.skim(to);
    }

    function V2PoolHandler_swapToken0(uint256 senderIndexSeed, uint256 amount) public {
        address to = randomAddress(senderIndexSeed);
        if (_quoteToken.balanceOf(to) < 1e14) return;
        amount = bound(amount, 1e14, _quoteToken.balanceOf(to));

        IUniswapV2Pair pool =
            IUniswapV2Pair(_uniV2Factory.getPair(address(_quoteToken), address(_baseToken)));
        if (address(pool) == address(0)) return;

        vm.prank(to);
        _quoteToken.approve(address(_uniV2Router), amount);

        address[] memory path = new address[](2);
        path[0] = address(_quoteToken);
        path[1] = address(_baseToken);

        vm.prank(to);
        try _uniV2Router.swapExactTokensForTokens(amount, 0, path, to, block.timestamp) {} catch {}
    }

    function V2PoolHandler_swapToken1(uint256 senderIndexSeed, uint256 amount) public {
        address to = randomAddress(senderIndexSeed);
        if (_baseToken.balanceOf(to) < 1e14) return;
        amount = bound(amount, 1e14, _baseToken.balanceOf(to));

        IUniswapV2Pair pool =
            IUniswapV2Pair(_uniV2Factory.getPair(address(_quoteToken), address(_baseToken)));
        if (address(pool) == address(0)) return;

        vm.prank(to);
        _baseToken.approve(address(_uniV2Router), amount);

        address[] memory path = new address[](2);
        path[0] = address(_baseToken);
        path[1] = address(_quoteToken);

        vm.prank(to);
        try _uniV2Router.swapExactTokensForTokens(amount, 0, path, to, block.timestamp) {} catch {}
    }
}
