// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";
import {FullMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/FullMath.sol";

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
        uint256 quoteTokenRemaining = quoteTokenAmount_;
        uint256 baseTokenRemaining = baseTokenAmount_;
        {
            // May be zero
            (uint256 mintQuoteTokens, uint256 mintBaseTokens) = _mintInitialLiquidity(
                IUniswapV2Pair(pairAddress),
                quoteToken_,
                quoteTokenAmount_,
                baseToken_,
                baseTokenAmount_
            );

            // Update the remaining amounts
            quoteTokenRemaining -= mintQuoteTokens;
            baseTokenRemaining -= mintBaseTokens;
        }

        // Calculate the minimum amount out for each token
        uint256 quoteTokenAmountMin =
            _getAmountWithSlippage(quoteTokenRemaining, params.maxSlippage);
        uint256 baseTokenAmountMin = _getAmountWithSlippage(baseTokenRemaining, params.maxSlippage);

        // Approve the router to spend the tokens
        ERC20(quoteToken_).approve(address(uniV2Router), quoteTokenRemaining);
        ERC20(baseToken_).approve(address(uniV2Router), baseTokenRemaining);

        // Deposit into the pool
        uniV2Router.addLiquidity(
            quoteToken_,
            baseToken_,
            quoteTokenRemaining,
            baseTokenRemaining,
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
    /// @param  quoteTokenAmount_   The amount of quote token
    /// @param  baseToken_          The base token
    /// @param  baseTokenAmount_    The amount of base token
    /// @return mintQuoteTokens     The amount of quote token minted
    /// @return mintBaseTokens      The amount of base token minted
    function _mintInitialLiquidity(
        IUniswapV2Pair pair_,
        address quoteToken_,
        uint256 quoteTokenAmount_,
        address baseToken_,
        uint256 baseTokenAmount_
    ) internal returns (uint256, uint256) {
        // Calculate the minimum required
        (uint256 mintQuoteTokens, uint256 mintBaseTokens) =
            _getMintAmounts(pair_, quoteToken_, quoteTokenAmount_, baseToken_, baseTokenAmount_);

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

        // Mint
        // The resulting LP will be transferred to this contract
        // The transfer or vesting of the LP will be subsequently handled
        pair_.mint(address(this));

        return (mintQuoteTokens, mintBaseTokens);
    }

    /// @notice Returns the number of tokens required to adjust the balance in `pair_` to `target_`.
    ///
    /// @param  token_          The token
    /// @param  pair_           The Uniswap V2 pair
    /// @param  target_         The target amount
    /// @return tokensRequired  The number of tokens required
    function _getTokensRequired(
        address token_,
        address pair_,
        uint256 target_
    ) internal view returns (uint256) {
        // Calculate the amount of token required to meet `target_`
        // We do not exclude the reserve value here, as the total balance needs to meet the target
        return target_ - ERC20(token_).balanceOf(pair_);
    }

    /// @notice Returns a multiplier for the balance of a token
    /// @dev    Scenario 1:
    ///         The comparison value is 3e18.
    ///         The token has a balance of 2e18 and a reserve of 1e18.
    ///         This function would return 0, as (2e18 - 1e18) / 3e18 is rounded down to 0.
    ///
    ///         Scenario 2:
    ///         The comparison value is 3e18.
    ///         The token has a balance of 4e18 and a reserve of 1e18.
    ///         This function would return 1, as (4e18 - 1e18) / 3e18 is rounded down to 1.
    ///
    /// @param  comparison_ The comparison value
    /// @param  location_   The location of the token
    /// @param  token_      The token
    /// @param  reserve_    The reserve of the token
    /// @return multiplier  The balance multiplier without decimal scale
    function _getBalanceMultiplier(
        uint256 comparison_,
        address location_,
        address token_,
        uint256 reserve_
    ) internal view returns (uint256) {
        uint256 balance = ERC20(token_).balanceOf(location_);
        // This should not be possible, but we check just in case
        if (balance <= reserve_) {
            return 0;
        }
        return (balance - reserve_) / comparison_;
    }

    /// @notice Calculates the minimum amount of quote token and base token for an initial deposit
    /// @dev    Minting the minimum amount of liquidity prevents the revert in `UniswapV2Library.quote()`.
    ///         Much of the function replicates logic from `UniswapV2Pair.mint()`.
    ///
    /// @param  pair_               The Uniswap V2 pair
    /// @param  quoteToken_         The quote token
    /// @param  baseToken_          The base token
    /// @return quoteTokenAmount    The amount of quote token
    /// @return baseTokenAmount     The amount of base token
    function _getMintAmounts(
        IUniswapV2Pair pair_,
        address quoteToken_,
        uint256 quoteTokenAmount_,
        address baseToken_,
        uint256 baseTokenAmount_
    ) internal view returns (uint256, uint256) {
        // Determine current reserves
        uint256 quoteTokenReserve;
        uint256 baseTokenReserve;
        {
            (uint112 reserve0, uint112 reserve1,) = pair_.getReserves();

            // If there are valid reserves, we do not need to do a manual mint
            if (reserve0 > 0 && reserve1 > 0) {
                return (0, 0);
            }

            // If there are no reserves, we do not need to do a manual mint
            if (reserve0 == 0 && reserve1 == 0) {
                return (0, 0);
            }

            bool quoteTokenIsToken0 = pair_.token0() == quoteToken_;
            quoteTokenReserve = quoteTokenIsToken0 ? reserve0 : reserve1;
            baseTokenReserve = quoteTokenIsToken0 ? reserve1 : reserve0;

            console2.log("quoteTokenReserve", quoteTokenReserve);
            console2.log("baseTokenReserve", baseTokenReserve);
        }

        // Determine the auction price (in terms of quote tokens)
        console2.log("quoteTokenAmount_", quoteTokenAmount_);
        console2.log("baseTokenAmount_", baseTokenAmount_);
        uint256 auctionPrice =
            FullMath.mulDiv(quoteTokenAmount_, 10 ** ERC20(baseToken_).decimals(), baseTokenAmount_);
        console2.log("auctionPrice", auctionPrice);

        // We need to provide enough tokens to match the minimum liquidity
        // The tokens also need to be in the correct proportion to set the price
        // The `UniswapV2Pair.mint()` function ignores existing reserves, so we need to take that into account
        // Additionally, there could be reserves that are donated, but not synced

        // Determine which token has a higher balance multiplier
        // This will be used to calculate the amount of tokens required
        uint256 multiplier;
        {
            uint256 quoteTokenMultiplier =
                _getBalanceMultiplier(auctionPrice, address(pair_), quoteToken_, quoteTokenReserve);
            console2.log("quoteTokenMultiplier", quoteTokenMultiplier);
            uint256 baseTokenMultiplier =
                _getBalanceMultiplier(auctionPrice, address(pair_), baseToken_, baseTokenReserve);
            console2.log("baseTokenMultiplier", baseTokenMultiplier);

            multiplier = (
                quoteTokenMultiplier > baseTokenMultiplier
                    ? quoteTokenMultiplier
                    : baseTokenMultiplier
            ) + 1;
            console2.log("multiplier", multiplier);
        }

        // Calculate the amount of tokens required
        // This takes into account the existing balances and reserves
        uint256 quoteTokensRequired =
            _getTokensRequired(quoteToken_, address(pair_), auctionPrice * multiplier);
        console2.log("quoteTokensRequired", quoteTokensRequired);
        uint256 baseTokensRequired = _getTokensRequired(
            baseToken_, address(pair_), (10 ** ERC20(baseToken_).decimals()) * multiplier
        );
        console2.log("baseTokensRequired", baseTokensRequired);

        // In isolation, the aim would be to reduce the amount of tokens required to meet the minimum liquidity
        // However, the pair could have an existing non-reserve balance in excess of that required for minimum liquidity. The mint function would automatically deposit the excess balance into reserves, which would result in an incorrect price.
        // To prevent this, we calculate the minimum liquidity required to set the price correctly
        return (quoteTokensRequired, baseTokensRequired);
    }
}
