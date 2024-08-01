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
            uint256 auctionPrice = FullMath.mulDiv(
                quoteTokenAmount_, 10 ** ERC20(baseToken_).decimals(), baseTokenAmount_
            );

            // May be zero
            (uint256 quoteTokensUsed, uint256 baseTokensUsed) = _mintInitialLiquidity(
                IUniswapV2Pair(pairAddress), quoteToken_, baseToken_, auctionPrice
            );
            console2.log("quoteTokensUsed", quoteTokensUsed);
            console2.log("baseTokensUsed", baseTokensUsed);

            // Calculate the amount of quote and base tokens to deposit as liquidity, while staying in proportion
            // This is because the adjustment of the balance in `_mintInitialLiquidity()` may not have required a proportional deposit
            if (quoteTokensUsed > 0 && baseTokensUsed > 0) {
                // We want to maximise the number of quote tokens added to the pool
                quoteTokensToAdd = quoteTokenAmount_ - quoteTokensUsed;
                console2.log("quoteTokensToAdd", quoteTokensToAdd);

                // Calculate the base tokens accordingly
                baseTokensToAdd = FullMath.mulDiv(
                    quoteTokensToAdd, 10 ** ERC20(baseToken_).decimals(), auctionPrice
                );
                console2.log("baseTokensToAdd", baseTokensToAdd);
            }
            // Otherwise the full amounts will be used
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

    /// @notice Mints initial liquidity to the pool in order to mitigate denial-of-service attacks
    /// @dev    Using `UniswapV2Router.addLiquidity()` initially allows for an external actor to donate 1 (or more) wei of the reserve token, call `IUniswapV2Pair.sync()` and DoS the settlement.
    ///         Instead, we mint the minimum liquidity to the pool, to prevent the revert in `UniswapV2Library.quote()`.
    ///
    /// @param  pair_               The Uniswap V2 pair
    /// @param  quoteToken_         The quote token
    /// @param  baseToken_          The base token
    /// @param  auctionPrice_       The auction price (quote tokens per base token)
    /// @return mintQuoteTokens     The amount of quote token minted
    /// @return mintBaseTokens      The amount of base token minted
    function _mintInitialLiquidity(
        IUniswapV2Pair pair_,
        address quoteToken_,
        address baseToken_,
        uint256 auctionPrice_
    ) internal returns (uint256, uint256) {
        // Calculate the minimum required
        (uint256 mintQuoteTokens, uint256 mintBaseTokens) =
            _getMintAmounts(address(pair_), quoteToken_, baseToken_, auctionPrice_);
        console2.log("mintQuoteTokens", mintQuoteTokens);
        console2.log("mintBaseTokens", mintBaseTokens);

        // Only proceed if required
        if (mintQuoteTokens == 0 && mintBaseTokens == 0) {
            return (0, 0);
        }

        // Transfer into the pool
        // There could be values of both the quote and base tokens, in order to get the reserves into the correct proportion
        if (mintQuoteTokens > 0) {
            ERC20(quoteToken_).transfer(address(pair_), mintQuoteTokens);
        }
        if (mintBaseTokens > 0) {
            ERC20(baseToken_).transfer(address(pair_), mintBaseTokens);
        }
        console2.log("transferred");
        {
            (uint112 reserve0, uint112 reserve1,) = pair_.getReserves();
            console2.log("reserve0", reserve0);
            console2.log("reserve1", reserve1);
        }

        // Mint
        // The resulting LP will be transferred to this contract
        // The transfer or vesting of the LP will be subsequently handled
        console2.log("minting");
        pair_.mint(address(this));

        return (mintQuoteTokens, mintBaseTokens);
    }

    /// @notice Calculates the minimum amount of quote token and base token for an initial deposit
    /// @dev    Minting the minimum amount of liquidity prevents the revert in `UniswapV2Library.quote()`.
    ///         Much of the function replicates logic from `UniswapV2Pair.mint()`.
    ///
    /// @param  location_           The location to check the balance of
    /// @param  quoteToken_         The quote token
    /// @param  baseToken_          The base token
    /// @return quoteTokenAmount    The amount of quote token
    /// @return baseTokenAmount     The amount of base token
    function _getMintAmounts(
        address location_,
        address quoteToken_,
        address baseToken_,
        uint256 auctionPrice_
    ) internal view returns (uint256, uint256) {
        // Determine if the reserves are in a state where this is needed
        {
            (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(location_).getReserves();

            // If there are no reserves, we do not need to do a manual mint
            if (reserve0 == 0 && reserve1 == 0) {
                return (0, 0);
            }
        }

        // Find the combination of token amounts that would result in the correct price, while meeting the minimum liquidity (1e3) required by UniswapV2Pair.mint()

        // We know that:
        // sqrt(quoteTokenAmount * baseTokenAmount) >= 1e3
        // quoteTokenAmount * baseTokenAmount >= 1e6
        //
        // To determine the quoteTokenAmount:
        // baseTokenAmount = quoteTokenAmount / auctionPrice
        // quoteTokenAmount^2 / auctionPrice >= 1e6
        // quoteTokenAmount >= sqrt(1e6 * auctionPrice)

        // First, get the quantity of quote tokens required to meet the minimum liquidity value, adjusting for decimals
        // We round up for the mulDiv and sqrt, to ensure the amounts are more than the minimum liquidity value
        // We also multiply by 2 wei to ensure that the amount is above the minimum liquidity value
        uint256 quoteTokenAmountMinimum = Math.sqrt(
            FullMath.mulDivRoundingUp(1e6, auctionPrice_, 10 ** ERC20(baseToken_).decimals()),
            Math.Rounding.Up
        ) * 2;
        console2.log("quoteTokenAmountMinimum", quoteTokenAmountMinimum);
        uint256 baseTokenAmountMinimum = FullMath.mulDivRoundingUp(
            quoteTokenAmountMinimum, 10 ** ERC20(baseToken_).decimals(), auctionPrice_
        );
        console2.log("baseTokenAmountMinimum", baseTokenAmountMinimum);

        // TODO multiply by 2 (raw) to go over minimum liquidity

        uint256 quoteTokenBalance;
        {
            quoteTokenBalance = ERC20(quoteToken_).balanceOf(location_);
            console2.log("quoteTokenBalance", quoteTokenBalance);

            // Deduct reserves, which are not considered
            (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(location_).getReserves();
            if (quoteToken_ == IUniswapV2Pair(location_).token0()) {
                console2.log("reserve0", reserve0);
                quoteTokenBalance -= reserve0;
            } else {
                console2.log("reserve1", reserve1);
                quoteTokenBalance -= reserve1;
            }
            console2.log("quoteTokenBalance less reserves", quoteTokenBalance);
        }
        // If the balance of the quote token is less than required, then we just need to transfer the difference and mint
        // We have a hard assumption that the base token is not circulating (yet), so we don't need to check the balance
        if (quoteTokenBalance < quoteTokenAmountMinimum) {
            console2.log("quoteTokenBalance less than minimum");
            return (quoteTokenAmountMinimum - quoteTokenBalance, baseTokenAmountMinimum);
        }

        // Otherwise, we determine how many base tokens are needed to be proportional to the quote token balance
        uint256 baseTokensRequired = FullMath.mulDivRoundingUp(
            quoteTokenBalance, 10 ** ERC20(baseToken_).decimals(), auctionPrice_
        );
        console2.log("baseTokensRequired", baseTokensRequired);

        return (0, baseTokensRequired);
    }
}
