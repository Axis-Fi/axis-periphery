// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

/// @dev Generated from https://arbiscan.io/address/0x0e216dd4f1b5ea81006d41b79f9a1a69a38f3e37
interface IRamsesV1Router {
    struct route {
        address from;
        address to;
        bool stable;
    }

    event Initialized(uint8 version);

    receive() external payable;

    function UNSAFE_swapExactTokensForTokens(
        uint256[] memory amounts,
        route[] memory routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory);
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
    function addLiquidityETH(
        address token,
        bool stable,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
    function factory() external view returns (address);
    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 amount, bool stable);
    function getAmountsOut(
        uint256 amountIn,
        route[] memory routes
    ) external view returns (uint256[] memory amounts);
    function getReserves(
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (uint256 reserveA, uint256 reserveB);
    function initialize(address _factory, address _weth) external;
    function isPair(address pair) external view returns (bool);
    function pairFor(
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (address pair);
    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external view returns (uint256 amountA, uint256 amountB, uint256 liquidity);
    function quoteRemoveLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity
    ) external view returns (uint256 amountA, uint256 amountB);
    function recoverFunds(address token, address to, uint256 amount) external;
    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
    function removeLiquidityETH(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);
    function removeLiquidityETHWithPermit(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);
    function sortTokens(
        address tokenA,
        address tokenB
    ) external pure returns (address token0, address token1);
    function swapExactETHForTokens(
        uint256 amountOutMin,
        route[] memory routes,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        route[] memory routes,
        address to,
        uint256 deadline
    ) external payable;
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        route[] memory routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        route[] memory routes,
        address to,
        uint256 deadline
    ) external;
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        route[] memory routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapExactTokensForTokensSimple(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        route[] memory routes,
        address to,
        uint256 deadline
    ) external;
    function weth() external view returns (address);
}