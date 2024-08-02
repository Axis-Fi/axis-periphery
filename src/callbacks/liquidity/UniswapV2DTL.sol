// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";
import {FullMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/FullMath.sol";
import {Math} from "@openzeppelin-contracts-4.9.2/utils/math/Math.sol";

// Uniswap
import {IUniswapV2Factory} from "@uniswap-v2-core-1.0.1/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap-v2-core-1.0.1/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@uniswap-v2-periphery-1.0.1/interfaces/IUniswapV2Router02.sol";

// Callbacks
import {BaseDirectToLiquidity} from "./BaseDTL.sol";

import {console2} from "@forge-std-1.9.1/console2.sol";

/// @title      UniswapV2DirectToLiquidity
/// @notice     This Callback contract deposits the proceeds from a batch auction into a Uniswap V2 pool
///             in order to create liquidity immediately.
///
///             The LP tokens are transferred to `DTLConfiguration.recipient`, or can optionally vest to the auction seller.
///
///             An important risk to consider: if the auction's base token is available and liquid, a third-party
///             could front-run the auction by creating the pool before the auction ends. This would allow them to
///             manipulate the price of the pool and potentially profit from the eventual deposit of the auction proceeds.
///
/// @dev        As a general rule, this callback contract does not retain balances of tokens between calls.
///             Transfers are performed within the same function that requires the balance.
contract UniswapV2DirectToLiquidity is BaseDirectToLiquidity {
    // ========== STRUCTS ========== //

    /// @notice     Parameters for the onCreate callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      maxSlippage     The maximum slippage allowed when adding liquidity (in terms of basis points, where 1% = 1e2)
    struct UniswapV2OnCreateParams {
        uint24 maxSlippage;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The Uniswap V2 factory
    /// @dev        This contract is used to create Uniswap V2 pools
    IUniswapV2Factory public uniV2Factory;

    /// @notice     The Uniswap V2 router
    /// @dev        This contract is used to add liquidity to Uniswap V2 pools
    IUniswapV2Router02 public uniV2Router;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address uniswapV2Factory_,
        address uniswapV2Router_
    ) BaseDirectToLiquidity(auctionHouse_) {
        if (uniswapV2Factory_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        uniV2Factory = IUniswapV2Factory(uniswapV2Factory_);

        if (uniswapV2Router_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        uniV2Router = IUniswapV2Router02(uniswapV2Router_);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function implements the following:
    ///             - Validates the parameters
    ///
    ///             This function reverts if:
    ///             - The callback data is of the incorrect length
    ///             - `UniswapV2OnCreateParams.maxSlippage` is out of bounds
    ///
    ///             Note that this function does not check if the pool already exists. The reason for this is that it could be used as a DoS vector.
    function __onCreate(
        uint96 lotId_,
        address,
        address,
        address,
        uint256,
        bool,
        bytes calldata
    ) internal virtual override {
        UniswapV2OnCreateParams memory params = _decodeOnCreateParameters(lotId_);

        // Check that the slippage amount is within bounds
        // The maxSlippage is stored during onCreate, as the callback data is passed in by the auction seller.
        // As AuctionHouse.settle() can be called by anyone, a value for maxSlippage could be passed that would result in a loss for the auction seller.
        if (params.maxSlippage > ONE_HUNDRED_PERCENT) {
            revert Callback_Params_PercentOutOfBounds(params.maxSlippage, 0, ONE_HUNDRED_PERCENT);
        }
    }

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function implements the following:
    ///             - Creates the pool if necessary
    ///             - Deposits the tokens into the pool
    function _mintAndDeposit(
        uint96 lotId_,
        address quoteToken_,
        uint256 quoteTokenAmount_,
        address baseToken_,
        uint256 baseTokenAmount_,
        bytes memory
    ) internal virtual override returns (ERC20 poolToken) {
        // Decode the callback data
        UniswapV2OnCreateParams memory params = _decodeOnCreateParameters(lotId_);

        // Create and initialize the pool if necessary
        // Token orientation is irrelevant
        address pairAddress = uniV2Factory.getPair(baseToken_, quoteToken_);
        if (pairAddress == address(0)) {
            pairAddress = uniV2Factory.createPair(baseToken_, quoteToken_);
        }

        // Handle a potential DoS attack
        uint256 quoteTokensToAdd = quoteTokenAmount_;
        uint256 baseTokensToAdd = baseTokenAmount_;
        {
            (uint256 quoteTokensUsed, uint256 baseTokensUsed) = _mitigateDonation(
                pairAddress,
                FullMath.mulDiv(
                    quoteTokenAmount_, 10 ** ERC20(baseToken_).decimals(), baseTokenAmount_
                ),
                quoteToken_,
                baseToken_
            );

            quoteTokensToAdd -= quoteTokensUsed;
            baseTokensToAdd -= baseTokensUsed;
        }

        // Calculate the minimum amount out for each token
        uint256 quoteTokenAmountMin = _getAmountWithSlippage(quoteTokensToAdd, params.maxSlippage);
        uint256 baseTokenAmountMin = _getAmountWithSlippage(baseTokensToAdd, params.maxSlippage);

        // Approve the router to spend the tokens
        ERC20(quoteToken_).approve(address(uniV2Router), quoteTokensToAdd);
        ERC20(baseToken_).approve(address(uniV2Router), baseTokensToAdd);

        // Deposit into the pool
        uniV2Router.addLiquidity(
            quoteToken_,
            baseToken_,
            quoteTokensToAdd,
            baseTokensToAdd,
            quoteTokenAmountMin,
            baseTokenAmountMin,
            address(this),
            block.timestamp
        );

        // Remove any dangling approvals
        // This is necessary, since the router may not spend all available tokens
        ERC20(quoteToken_).approve(address(uniV2Router), 0);
        ERC20(baseToken_).approve(address(uniV2Router), 0);

        return ERC20(pairAddress);
    }

    /// @notice Decodes the configuration parameters from the DTLConfiguration
    /// @dev   The configuration parameters are stored in `DTLConfiguration.implParams`
    function _decodeOnCreateParameters(uint96 lotId_)
        internal
        view
        returns (UniswapV2OnCreateParams memory)
    {
        DTLConfiguration memory lotConfig = lotConfiguration[lotId_];
        // Validate that the callback data is of the correct length
        if (lotConfig.implParams.length != 32) {
            revert Callback_InvalidParams();
        }

        return abi.decode(lotConfig.implParams, (UniswapV2OnCreateParams));
    }

    function _calculateDesiredPoolPostSwapReserves(
        address pairAddress_,
        uint256 auctionPrice_,
        address quoteToken_,
        address baseToken_
    ) internal view returns (uint256 desiredQuoteTokenReserves, uint256 desiredBaseTokenReserves) {
        uint256 quoteTokenReserves;
        uint256 baseTokenReserves;
        {
            IUniswapV2Pair pair = IUniswapV2Pair(pairAddress_);
            (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

            quoteTokenReserves = pair.token0() == quoteToken_ ? reserve0 : reserve1;
            baseTokenReserves = pair.token0() == baseToken_ ? reserve0 : reserve1;
        }

        // Calculate the liquidity hurdle
        // TODO handle fees
        uint256 liquidityHurdle = quoteTokenReserves * baseTokenReserves;
        console2.log("liquidityHurdle", liquidityHurdle);

        uint256 quoteTokenScale = 10 ** ERC20(quoteToken_).decimals();
        uint256 baseTokenScale = 10 ** ERC20(baseToken_).decimals();

        // Use the auction price to determine a quantity of quote tokens that would be required to reach the desired liquidity hurdle
        // Since quoteTokenAmount / baseTokenAmount = auctionPrice
        // quoteTokenAmount = auctionPrice * baseTokenAmount
        // auctionPrice * baseTokenAmount * baseTokenAmount >= liquidity hurdle
        // baseTokenAmount^2 >= liquidity hurdle / auctionPrice
        // baseTokenAmount >= sqrt(liquidity hurdle / auctionPrice)
        desiredBaseTokenReserves = Math.sqrt(liquidityHurdle * quoteTokenScale / auctionPrice_);

        // From that, we can calculate the required quote token balance
        desiredQuoteTokenReserves = auctionPrice_ * desiredBaseTokenReserves / baseTokenScale;

        // Example:
        // quoteTokenReserves = 3e18 (18 dp)
        // baseTokenReserves = 1 (17 dp)
        // liquidityHurdle = 3e18 * 1 = 3e18
        // auctionPrice = 2e18 (18 dp)
        // desiredBaseTokenReserves = sqrt(3e18 * 1e18 / 2e18) = sqrt(1.5e18) = 1.22e18

        console2.log("desiredQuoteTokenReserves", desiredQuoteTokenReserves);
        console2.log("desiredBaseTokenReserves", desiredBaseTokenReserves);

        return (desiredQuoteTokenReserves, desiredBaseTokenReserves);
    }

    function _calculatePoolTransfers(
        address pairAddress_,
        uint256 auctionPrice_,
        address quoteToken_,
        address baseToken_
    )
        internal
        view
        returns (
            uint256 quoteTokensToTransferIn,
            uint256 baseTokensToTransferIn,
            uint256 quoteTokenBalanceDesired
        )
    {
        // The product of the post-swap balances (minus the fee) needs to be >= the product of the pre-swap reserves

        uint256 liquidityHurdle;
        {
            (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pairAddress_).getReserves();
            liquidityHurdle = reserve0 * reserve1 * 1000**2;
        }

        console2.log("auctionPrice", auctionPrice_);
        // Convert the auction price to wei
        // TODO: loss of precision if the price is a decimal number. Consider how to handle this.
        uint256 auctionPriceWei =
            Math.mulDiv(auctionPrice_, 1, 10 ** ERC20(quoteToken_).decimals(), Math.Rounding.Up);
        console2.log("auctionPriceWei", auctionPriceWei);

        // If the auction price is greater than 1, we need to ensure that the pool has at least that price in wei
        // e.g. price of 3 means that 3 wei of quote tokens are required for 1 wei of base token
        if (auctionPrice_ > 10 ** ERC20(quoteToken_).decimals()) {
            console2.log("price > 1");
            // Calculate the amount of quote tokens required
            uint256 quoteTokenPoolBalance = ERC20(quoteToken_).balanceOf(pairAddress_);
            console2.log("quoteTokenPoolBalance", quoteTokenPoolBalance);
            if (quoteTokenPoolBalance < auctionPriceWei) {
                quoteTokensToTransferIn = auctionPriceWei - quoteTokenPoolBalance;
            }

            baseTokensToTransferIn = 1;
            quoteTokenBalanceDesired = auctionPriceWei;
        }
        // If the auction price is less than 1, then there will be enough quote tokens in the pool
        // e.g. price of 0.5 means that 1 quote token is required for 2 base tokens
        else if (auctionPrice_ < 10 ** ERC20(quoteToken_).decimals()) {
            console2.log("price < 1");
            // The number of base tokens required will be 1 / auction price in base token decimals
            // e.g. 0.5 means that 2 base tokens are required for 1 quote token
            // TODO handle decimals
            baseTokensToTransferIn =
                Math.mulDiv(1, 10 ** ERC20(baseToken_).decimals(), auctionPrice_, Math.Rounding.Up);

            quoteTokenBalanceDesired = 1;
        }
        // If the auction price is equal to 1, then there will be enough quote tokens in the pool
        else {
            console2.log("price = 1");
            // Base tokens will need to be transferred in
            baseTokensToTransferIn = 1;
            quoteTokenBalanceDesired = 1;
        }

        console2.log("quoteTokensToTransferIn", quoteTokensToTransferIn);
        console2.log("baseTokensToTransferIn", baseTokensToTransferIn);
        console2.log("quoteTokenBalanceDesired", quoteTokenBalanceDesired);
    }

    function _mitigateDonation(
        address pairAddress_,
        uint256 auctionPrice_,
        address quoteToken_,
        address baseToken_
    ) internal returns (uint256 quoteTokensUsed, uint256 baseTokensUsed) {
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress_);
        {
            // Check if the pool has had quote tokens donated
            // Base tokens are not liquid, so we don't need to check for them
            (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
            uint112 quoteTokenReserve = pair.token0() == quoteToken_ ? reserve0 : reserve1;

            if (quoteTokenReserve == 0) {
                return (0, 0);
            }
        }

        // If there has been a donation into the pool, we need to adjust the reserves so that the price is correct
        // This can be performed by swapping the quote tokens for base tokens
        // The pool also needs to have a minimum amount of liquidity for the swap to succeed

        // To perform the swap, both reserves need to be non-zero, so we need to transfer in some tokens and update the reserves
        {
            ERC20(baseToken_).transfer(pairAddress_, 1);
            pair.sync();
            baseTokensUsed += 1;
        }

        // We first calculate the desired end state of the pool after the swap
        (
            uint256 desiredQuoteTokenReserves,
            uint256 desiredBaseTokenReserves
        ) = _calculateDesiredPoolPostSwapReserves(pairAddress_, auctionPrice_, quoteToken_, baseToken_);

        // Handle quote token transfers
        uint256 quoteTokensOut;
        {
            uint256 quoteTokenBalance = ERC20(quoteToken_).balanceOf(pairAddress_);

            // TODO consider if this can underflow
            quoteTokensOut = quoteTokenBalance - desiredQuoteTokenReserves;
            console2.log("quoteTokensOut", quoteTokensOut);
        }

        // Handle base token transfers
        {
            uint256 baseTokensToTransfer = desiredBaseTokenReserves - ERC20(baseToken_).balanceOf(pairAddress_);
            if (baseTokensToTransfer > 0) {
                ERC20(baseToken_).transfer(pairAddress_, baseTokensToTransfer);
                baseTokensUsed += baseTokensToTransfer;
            }
            console2.log("baseTokensToTransfer", baseTokensToTransfer);
        }

        // Perform the swap
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        console2.log("reserve0", reserve0);
        console2.log("reserve1", reserve1);

        uint256 amount0Out = pair.token0() == quoteToken_ ? quoteTokensOut : 0;
        uint256 amount1Out = pair.token0() == quoteToken_ ? 0 : quoteTokensOut;
        console2.log("amount0Out", amount0Out);
        console2.log("amount1Out", amount1Out);
        uint256 balance0 = ERC20(pair.token0()).balanceOf(address(pair)) - amount0Out;
        uint256 balance1 = ERC20(pair.token1()).balanceOf(address(pair)) - amount1Out;
        console2.log("balance0", balance0);
        console2.log("balance1", balance1);

        uint256 amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;
        console2.log("amount0In", amount0In);
        console2.log("amount1In", amount1In);

        uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
        console2.log("balance0Adjusted", balance0Adjusted);
        console2.log("balance1Adjusted", balance1Adjusted);

        console2.log("new liquidity", balance0Adjusted * balance1Adjusted);
        console2.log("current liquidity", reserve0 * reserve1 * 1000**2);

        pair.swap(
            amount0Out,
            amount1Out,
            address(this),
            ""
        );

        // Do not adjust the quote tokens used in the subsequent liquidity deposit, as they could shift the price
        // These tokens will be transferred to the seller during cleanup
    }
}
