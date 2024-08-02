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
            // Check if the pool has had quote tokens donated
            // Base tokens are not liquid, so we don't need to check for them
            IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
            (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
            uint112 quoteTokenReserve = pair.token0() == quoteToken_ ? reserve0 : reserve1;
            console2.log("quoteTokenReserve", quoteTokenReserve);
            if (quoteTokenReserve > 0) {
                // Calculate the auction price (quote tokens per base token)
                uint256 auctionPrice = FullMath.mulDiv(
                    quoteTokenAmount_, 10 ** ERC20(baseToken_).decimals(), baseTokenAmount_
                );
                console2.log("auctionPrice", auctionPrice);
                // Convert the auction price to wei
                // TODO: loss of precision if the price is a decimal number. Consider how to handle this.
                uint256 auctionPriceWei = Math.mulDiv(
                    auctionPrice, 1, 10 ** ERC20(quoteToken_).decimals(), Math.Rounding.Up
                );
                console2.log("auctionPriceWei", auctionPriceWei);

                // Determine the amount of tokens to transfer to the pool
                uint256 quoteTokensToTransferIn;
                uint256 baseTokensToTransferIn;
                uint256 quoteTokenBalanceDesired;

                // If the auction price is greater than 1, we need to ensure that the pool has at least that price in wei
                // e.g. price of 3 means that 3 wei of quote tokens are required for 1 wei of base token
                if (auctionPrice > 10 ** ERC20(quoteToken_).decimals()) {
                    console2.log("price > 1");
                    // Calculate the amount of quote tokens required
                    uint256 quoteTokenPoolBalance = ERC20(quoteToken_).balanceOf(pairAddress);
                    if (quoteTokenPoolBalance < auctionPriceWei) {
                        quoteTokensToTransferIn = auctionPriceWei - quoteTokenPoolBalance;
                    }

                    baseTokensToTransferIn = 1;
                    quoteTokenBalanceDesired = auctionPriceWei;
                }
                // If the auction price is less than 1, then there will be enough quote tokens in the pool
                // e.g. price of 0.5 means that 1 quote token is required for 2 base tokens
                else if (auctionPrice < 10 ** ERC20(quoteToken_).decimals()) {
                    console2.log("price < 1");
                    // The number of base tokens required will be 1 / auction price in base token decimals
                    // e.g. 0.5 means that 2 base tokens are required for 1 quote token
                    // TODO handle decimals
                    baseTokensToTransferIn = Math.mulDiv(
                        1, 10 ** ERC20(baseToken_).decimals(), auctionPrice, Math.Rounding.Up
                    );

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

                // Transfer in the required amounts
                if (quoteTokensToTransferIn > 0) {
                    ERC20(quoteToken_).transfer(pairAddress, quoteTokensToTransferIn);
                    quoteTokensToAdd -= quoteTokensToTransferIn;
                }
                if (baseTokensToTransferIn > 0) {
                    ERC20(baseToken_).transfer(pairAddress, baseTokensToTransferIn);
                    baseTokensToAdd -= baseTokensToTransferIn;
                }

                // Perform the swap
                uint256 quoteTokenOut =
                    ERC20(quoteToken_).balanceOf(pairAddress) - quoteTokenBalanceDesired;
                pair.swap(
                    quoteToken_ == pair.token0() ? 0 : quoteTokenOut,
                    quoteToken_ == pair.token1() ? 0 : quoteTokenOut,
                    address(this),
                    ""
                );
            }
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
}
