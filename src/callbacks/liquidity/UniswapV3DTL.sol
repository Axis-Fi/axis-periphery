// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.7.0/utils/SafeTransferLib.sol";

// Uniswap
import {IUniswapV3Pool} from
    "@uniswap-v3-core-1.0.1-solc-0.8-simulate/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from
    "@uniswap-v3-core-1.0.1-solc-0.8-simulate/interfaces/IUniswapV3Factory.sol";
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";
import {SqrtPriceMath} from "../../lib/uniswap-v3/SqrtPriceMath.sol";

// G-UNI
import {IGUniFactory} from "@g-uni-v1-core-0.9.9/interfaces/IGUniFactory.sol";
import {GUniPool} from "@g-uni-v1-core-0.9.9/GUniPool.sol";

// Callbacks
import {BaseDirectToLiquidity} from "./BaseDTL.sol";

/// @title      UniswapV3DirectToLiquidity
/// @notice     This Callback contract deposits the proceeds from a batch auction into a Uniswap V3 pool
///             in order to create liquidity immediately.
///
///             The Uniswap V3 position is tokenised as an ERC-20 using [G-UNI](https://github.com/gelatodigital/g-uni-v1-core).
///
///             The LP tokens are transferred to `DTLConfiguration.recipient`, or can optionally vest to the auction seller.
///
///             An important risk to consider: if the auction's base token is available and liquid, a third-party
///             could front-run the auction by creating the pool before the auction ends. This would allow them to
///             manipulate the price of the pool and potentially profit from the eventual deposit of the auction proceeds.
///
/// @dev        As a general rule, this callback contract does not retain balances of tokens between calls.
///             Transfers are performed within the same function that requires the balance.
contract UniswapV3DirectToLiquidity is BaseDirectToLiquidity {
    using SafeTransferLib for ERC20;

    // ========== ERRORS ========== //

    error Callback_Params_PoolFeeNotEnabled();
    error Callback_Slippage(address token_, uint256 amountActual_, uint256 amountMin_);
    error Callback_Swap_InvalidData();
    error Callback_Swap_InvalidCaller();
    error Callback_Swap_InvalidCase();

    // ========== STRUCTS ========== //

    /// @notice     Parameters for the onCreate callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      poolFee                 The fee of the Uniswap V3 pool
    /// @param      maxSlippage             The maximum slippage allowed when adding liquidity (in terms of `ONE_HUNDRED_PERCENT`)
    struct UniswapV3OnCreateParams {
        uint24 poolFee;
        uint24 maxSlippage;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The Uniswap V3 Factory contract
    /// @dev        This contract is used to create Uniswap V3 pools
    IUniswapV3Factory public uniV3Factory;

    /// @notice     The G-UNI Factory contract
    /// @dev        This contract is used to create the ERC20 LP tokens
    IGUniFactory public gUniFactory;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address uniV3Factory_,
        address gUniFactory_
    ) BaseDirectToLiquidity(auctionHouse_) {
        if (uniV3Factory_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        uniV3Factory = IUniswapV3Factory(uniV3Factory_);

        if (gUniFactory_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        gUniFactory = IGUniFactory(gUniFactory_);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function performs the following:
    ///             - Validates the input data
    ///
    ///             This function reverts if:
    ///             - `UniswapV3OnCreateParams.poolFee` is not enabled
    ///             - `UniswapV3OnCreateParams.maxSlippage` is out of bounds
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
        UniswapV3OnCreateParams memory params = _decodeOnCreateParameters(lotId_);

        // Validate the parameters
        // Pool fee
        // Fee not enabled
        if (uniV3Factory.feeAmountTickSpacing(params.poolFee) == 0) {
            revert Callback_Params_PoolFeeNotEnabled();
        }

        // Check that the maxSlippage is in bounds
        // The maxSlippage is stored during onCreate, as the callback data is passed in by the auction seller.
        // As AuctionHouse.settle() can be called by anyone, a value for maxSlippage could be passed that would result in a loss for the auction seller.
        if (params.maxSlippage > ONE_HUNDRED_PERCENT) {
            revert Callback_Params_PercentOutOfBounds(params.maxSlippage, 0, ONE_HUNDRED_PERCENT);
        }
    }

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function performs the following:
    ///             - Creates and initializes the pool, if necessary
    ///             - Deploys a pool token to wrap the Uniswap V3 position as an ERC-20 using GUni
    ///             - Uses the `GUniPool.getMintAmounts()` function to calculate the quantity of quote and base tokens required, given the current pool liquidity
    ///             - Mint the LP tokens
    ///
    ///             The assumptions are:
    ///             - the callback has `quoteTokenAmount_` quantity of quote tokens (as `receiveQuoteTokens` flag is set)
    ///             - the callback has `baseTokenAmount_` quantity of base tokens
    function _mintAndDeposit(
        uint96 lotId_,
        address quoteToken_,
        uint256 quoteTokenAmount_,
        address baseToken_,
        uint256 baseTokenAmount_,
        bytes memory
    ) internal virtual override returns (ERC20 poolToken) {
        // Decode the callback data
        UniswapV3OnCreateParams memory params = _decodeOnCreateParameters(lotId_);

        // Determine the ordering of tokens
        bool quoteTokenIsToken0 = quoteToken_ < baseToken_;

        // Create and initialize the pool if necessary
        // This may involve swapping tokens to adjust the pool price
        // if it already exists and has single-sided quote token liquidity
        // provided.
        {
            // Determine sqrtPriceX96
            uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(
                quoteToken_, baseToken_, quoteTokenAmount_, baseTokenAmount_
            );

            // If the pool already exists and is initialized, it will have no effect
            // Please see the risks section in the contract documentation for more information
            (, uint256 quoteTokensReceived, uint256 baseTokensUsed) =
            _createAndInitializePoolIfNecessary(
                quoteToken_,
                baseToken_,
                quoteTokenIsToken0,
                baseTokenAmount_ / 2,
                params.poolFee,
                sqrtPriceX96
            );

            quoteTokenAmount_ += quoteTokensReceived;
            baseTokenAmount_ -= baseTokensUsed;
        }

        // Deploy the pool token
        address poolTokenAddress;
        {
            // Adjust the full-range ticks according to the tick spacing for the current fee
            int24 tickSpacing = uniV3Factory.feeAmountTickSpacing(params.poolFee);

            // Create an unmanaged pool
            // The range of the position will not be changed after deployment
            // Fees will also be collected at the time of withdrawal
            poolTokenAddress = gUniFactory.createPool(
                quoteTokenIsToken0 ? quoteToken_ : baseToken_,
                quoteTokenIsToken0 ? baseToken_ : quoteToken_,
                params.poolFee,
                TickMath.MIN_TICK / tickSpacing * tickSpacing,
                TickMath.MAX_TICK / tickSpacing * tickSpacing
            );
        }

        // Deposit into the pool
        {
            GUniPool gUniPoolToken = GUniPool(poolTokenAddress);

            // Calculate the quantity of quote and base tokens required to deposit into the pool at the current tick
            (uint256 amount0Actual, uint256 amount1Actual, uint256 poolTokenQuantity) =
            gUniPoolToken.getMintAmounts(
                quoteTokenIsToken0 ? quoteTokenAmount_ : baseTokenAmount_,
                quoteTokenIsToken0 ? baseTokenAmount_ : quoteTokenAmount_
            );

            // Revert if the slippage is too high
            {
                uint256 quoteTokenRequired = quoteTokenIsToken0 ? amount0Actual : amount1Actual;
                _approveMintAmount(
                    quoteToken_,
                    poolTokenAddress,
                    quoteTokenAmount_,
                    quoteTokenRequired,
                    params.maxSlippage
                );
            }
            {
                uint256 baseTokenRequired = quoteTokenIsToken0 ? amount1Actual : amount0Actual;
                _approveMintAmount(
                    baseToken_,
                    poolTokenAddress,
                    baseTokenAmount_,
                    baseTokenRequired,
                    params.maxSlippage
                );
            }

            // Mint the LP tokens
            // The parent callback is responsible for transferring any leftover quote and base tokens
            gUniPoolToken.mint(poolTokenQuantity, address(this));
        }

        poolToken = ERC20(poolTokenAddress);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @dev    Modified from UniswapV3's PoolInitializer (which is GPL >= 2)
    function _createAndInitializePoolIfNecessary(
        address quoteToken,
        address baseToken,
        bool quoteTokenIsToken0,
        uint256 maxBaseTokens,
        uint24 fee,
        uint160 sqrtPriceX96
    ) internal returns (address pool, uint256 quoteTokensReceived, uint256 baseTokensUsed) {
        address token0 = quoteTokenIsToken0 ? quoteToken : baseToken;
        address token1 = quoteTokenIsToken0 ? baseToken : quoteToken;
        pool = uniV3Factory.getPool(token0, token1, fee);

        if (pool == address(0)) {
            pool = uniV3Factory.createPool(token0, token1, fee);
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing,,,,,,) = IUniswapV3Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                IUniswapV3Pool(pool).initialize(sqrtPriceX96);
            } else {
                // if the pool already exists and is initialized, we need to make sure the price
                // is consistent with the price we would have initialized it with
                // the price comparison depends on which token is token0
                // because price is always expressed as the price of token0
                // in terms of token1
                //
                // there are 3 cases, represented here assuming price is in terms of quote tokens per base token
                // the opposite case is also handle in the same block
                // 1. actual price < target price
                if (
                    !quoteTokenIsToken0 && sqrtPriceX96Existing < sqrtPriceX96
                        || quoteTokenIsToken0 && sqrtPriceX96Existing > sqrtPriceX96
                ) {
                    // price in terms of quote tokens is lower than expected.
                    // we can swap net 0 quote tokens for base tokens
                    // and move the price to the target.
                    bytes memory data = abi.encode(quoteToken, baseToken, fee, 1);
                    IUniswapV3Pool(pool).swap(
                        address(this), // recipient -> this contract
                        quoteTokenIsToken0, // zeroForOne -> we are swapping quoteToken for baseToken
                        int256(1), // amountSpecified -> swap 1 wei of quote token (positive value means amountIn), this won't actually be used since there are no base tokens in the pool
                        sqrtPriceX96, // sqrtPriceLimitX96 -> the max price we will pay, this will move the pool price to the value provided
                        data // arbitrary data -> case 1
                    );
                }
                // 2. actual price > target price
                else if (
                    !quoteTokenIsToken0 && sqrtPriceX96Existing > sqrtPriceX96
                        || quoteTokenIsToken0 && sqrtPriceX96Existing < sqrtPriceX96
                ) {
                    // price is terms of quote tokens is higher than expected
                    // we need to sell up to half of the base tokens into the liquidity
                    // pool to move the price as close as possible to the target
                    // The amountDeltas represent the +/- change from the pool's perspective
                    // Negative values mean this contract received tokens and positive values mean it sent tokens
                    bytes memory data = abi.encode(quoteToken, baseToken, fee, 2);
                    (int256 amount0Delta, int256 amount1Delta) = IUniswapV3Pool(pool).swap(
                        address(this), // recipient -> this contract
                        !quoteTokenIsToken0, // zeroForOne -> we are swapping baseToken for quoteToken
                        int256(maxBaseTokens), // amountSpecified -> sell up to the max base tokens (positive value means amountIn)
                        sqrtPriceX96, // sqrtPriceLimitX96 -> the min price will we accept for the base tokens, depending on the amount of tokens to sell this will move at most down to the price provided
                        data // arbitrary data -> case 2
                    );

                    quoteTokensReceived =
                        uint256(quoteTokenIsToken0 ? -amount0Delta : -amount1Delta);
                    baseTokensUsed = uint256(quoteTokenIsToken0 ? amount1Delta : amount0Delta);
                }
                // 3. actual price == target price (where we don't need to do anything)
            }
        }
    }

    /// @notice Decodes the configuration parameters from the DTLConfiguration
    /// @dev   The configuration parameters are stored in `DTLConfiguration.implParams`
    function _decodeOnCreateParameters(
        uint96 lotId_
    ) internal view returns (UniswapV3OnCreateParams memory) {
        DTLConfiguration memory lotConfig = lotConfiguration[lotId_];
        // Validate that the callback data is of the correct length
        if (lotConfig.implParams.length != 64) {
            revert Callback_InvalidParams();
        }

        return abi.decode(lotConfig.implParams, (UniswapV3OnCreateParams));
    }

    /// @notice Approves the spender to spend the token amount with a maximum slippage
    /// @dev    This function reverts if the slippage is too high from the original amount
    ///
    /// @param  token_          The token to approve
    /// @param  spender_        The spender
    /// @param  amount_         The amount available
    /// @param  amountActual_   The actual amount required
    /// @param  maxSlippage_    The maximum slippage allowed
    function _approveMintAmount(
        address token_,
        address spender_,
        uint256 amount_,
        uint256 amountActual_,
        uint24 maxSlippage_
    ) internal {
        // Revert if the slippage is too high
        uint256 lower = _getAmountWithSlippage(amount_, maxSlippage_);
        if (amountActual_ < lower) {
            revert Callback_Slippage(token_, amountActual_, lower);
        }

        // Approve the vault to spend the tokens
        ERC20(token_).safeApprove(spender_, amountActual_);
    }

    // ========== UNIV3 FUNCTIONS ========== //

    // Provide tokens when adjusting the pool price via a swap before deploying liquidity
    function uniswapV3SwapCallback(
        int256 amount0Delta_,
        int256 amount1Delta_,
        bytes calldata data_
    ) external {
        // Data should be 4 words long
        if (data_.length != 128) revert Callback_Swap_InvalidData();

        // Decode the data
        (address quoteToken, address baseToken, uint24 fee, uint8 case_) =
            abi.decode(data_, (address, address, uint24, uint8));

        // Only the pool can call
        address token0 = quoteToken < baseToken ? quoteToken : baseToken;
        address token1 = quoteToken < baseToken ? baseToken : quoteToken;
        address pool = uniV3Factory.getPool(token0, token1, fee);
        if (msg.sender != pool) revert Callback_Swap_InvalidCaller();

        // Handle the swap case
        if (case_ == 1) {
            // Case 1: Swapped in 1 wei of quote tokens
            // We don't need to do anything here
        }
        else if (case_ == 2) {
            // Case 2: We sold up to half of the base tokens into the pool to move the price down
            // Transfer the requested token1 amount to the pool
            if (token0 == baseToken) {
                if (amount0Delta_ > 0) ERC20(baseToken).safeTransfer(pool, uint256(amount0Delta_));
            } else {
                if (amount1Delta_ > 0) ERC20(baseToken).safeTransfer(pool, uint256(amount1Delta_));
            }
        } else {
            revert Callback_Swap_InvalidCase();
        }
    }
}
