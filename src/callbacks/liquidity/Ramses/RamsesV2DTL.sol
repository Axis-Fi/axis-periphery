// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";

// Callbacks
import {BaseDirectToLiquidity} from "../BaseDTL.sol";

// Ramses
import {IRamsesV2Pool} from "./lib/IRamsesV2Pool.sol";
import {IRamsesV2Factory} from "./lib/IRamsesV2Factory.sol";
import {IRamsesV2PositionManager} from "./lib/IRamsesV2PositionManager.sol";

// Uniswap
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";
import {SqrtPriceMath} from "../../../lib/uniswap-v3/SqrtPriceMath.sol";

contract RamsesV2DirectToLiquidity is BaseDirectToLiquidity {
    // ========== ERRORS ========== //

    error Callback_Params_PoolFeeNotEnabled();

    // ========== STRUCTS ========== //

    /// @notice     Parameters for the onSettle callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      maxSlippage             The maximum slippage allowed when adding liquidity (in terms of `ONE_HUNDRED_PERCENT`)
    /// @param      veRamTokenId            The token ID of the veRAM token to use for the position (optional)
    struct OnSettleParams {
        uint24 maxSlippage;
        uint256 veRamTokenId;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The Ramses V2 factory
    IRamsesV2Factory public ramsesV2Factory;

    /// @notice     The Ramses V2 position manager
    IRamsesV2PositionManager public ramsesV2PositionManager;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address ramsesV2Factory_,
        address payable ramsesV2PositionManager_
    ) BaseDirectToLiquidity(auctionHouse_) {
        if (ramsesV2Factory_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        ramsesV2Factory = IRamsesV2Factory(ramsesV2Factory_);

        if (ramsesV2PositionManager_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        ramsesV2PositionManager = IRamsesV2PositionManager(ramsesV2PositionManager_);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function performs the following:
    ///             - Validates the input data
    ///
    ///             This function reverts if:
    ///             - OnCreateParams.implParams.poolFee is not enabled
    ///             - The pool for the token and fee combination already exists
    function __onCreate(
        uint96,
        address,
        address baseToken_,
        address quoteToken_,
        uint256,
        bool,
        bytes calldata callbackData_
    ) internal virtual override {
        OnCreateParams memory params = abi.decode(callbackData_, (OnCreateParams));
        uint24 poolFee = abi.decode(params.implParams, (uint24));

        // Validate the parameters
        // Pool fee
        // Fee not enabled
        if (ramsesV2Factory.feeAmountTickSpacing(poolFee) == 0) {
            revert Callback_Params_PoolFeeNotEnabled();
        }

        // Check that the pool does not exist
        if (ramsesV2Factory.getPool(baseToken_, quoteToken_, poolFee) != address(0)) {
            revert Callback_Params_PoolExists();
        }
    }

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function implements the following:
    ///             - Creates and initializes the pool, if necessary
    ///             - Creates a new position and adds liquidity
    ///             - Transfers the ERC721 pool token to the recipient
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
        bytes memory callbackData_
    ) internal virtual override {
        // Decode the callback data
        OnSettleParams memory params = abi.decode(callbackData_, (OnSettleParams));

        // Extract the pool fee from the implParams
        uint24 poolFee = abi.decode(lotConfiguration[lotId_].implParams, (uint24));

        // Determine the ordering of tokens
        bool quoteTokenIsToken0 = quoteToken_ < baseToken_;

        // Create and initialize the pool if necessary
        {
            // Determine sqrtPriceX96
            uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(
                quoteToken_, baseToken_, quoteTokenAmount_, baseTokenAmount_
            );

            // If the pool already exists and is initialized, it will have no effect
            // Please see the risks section in the contract documentation for more information
            _createAndInitializePoolIfNecessary(
                quoteTokenIsToken0 ? quoteToken_ : baseToken_,
                quoteTokenIsToken0 ? baseToken_ : quoteToken_,
                poolFee,
                sqrtPriceX96
            );
        }

        // Mint the position and add liquidity
        {
            IRamsesV2PositionManager.MintParams memory mintParams = _getMintParams(
                lotId_, quoteToken_, quoteTokenAmount_, baseToken_, baseTokenAmount_, params
            );

            // Approve spending
            ERC20(quoteToken_).approve(address(ramsesV2PositionManager), quoteTokenAmount_);
            ERC20(baseToken_).approve(address(ramsesV2PositionManager), baseTokenAmount_);

            // Mint the position
            ramsesV2PositionManager.mint(mintParams);

            // Reset dangling approvals
            // The position manager may not spend all tokens
            ERC20(quoteToken_).approve(address(ramsesV2PositionManager), 0);
            ERC20(baseToken_).approve(address(ramsesV2PositionManager), 0);
        }
    }

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function does not perform any actions,
    ///             as `_mintAndDeposit()` directly transfers the token to the recipient
    function _transferPoolToken(uint96) internal virtual override {
        // Nothing to do
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @dev    Copied from UniswapV3's PoolInitializer (which is GPL >= 2)
    function _createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) internal returns (address pool) {
        require(token0 < token1);
        pool = ramsesV2Factory.getPool(token0, token1, fee);

        if (pool == address(0)) {
            pool = ramsesV2Factory.createPool(token0, token1, fee);
            IRamsesV2Pool(pool).initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing,,,,,,) = IRamsesV2Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                IRamsesV2Pool(pool).initialize(sqrtPriceX96);
            }
        }
    }

    function _getMintParams(
        uint96 lotId_,
        address quoteToken_,
        uint256 quoteTokenAmount_,
        address baseToken_,
        uint256 baseTokenAmount_,
        OnSettleParams memory onSettleParams_
    ) internal view returns (IRamsesV2PositionManager.MintParams memory) {
        // Extract the pool fee from the implParams
        uint24 poolFee;
        int24 tickSpacing;
        {
            poolFee = abi.decode(lotConfiguration[lotId_].implParams, (uint24));
            tickSpacing = ramsesV2Factory.feeAmountTickSpacing(poolFee);
        }

        // Determine the ordering of tokens
        bool quoteTokenIsToken0 = quoteToken_ < baseToken_;

        // Calculate the minimum amount out for each token
        uint256 amount0 = quoteTokenIsToken0 ? quoteTokenAmount_ : baseTokenAmount_;
        uint256 amount1 = quoteTokenIsToken0 ? baseTokenAmount_ : quoteTokenAmount_;

        return IRamsesV2PositionManager.MintParams({
            token0: quoteTokenIsToken0 ? quoteToken_ : baseToken_,
            token1: quoteTokenIsToken0 ? baseToken_ : quoteToken_,
            fee: poolFee,
            tickLower: (TickMath.MIN_TICK / tickSpacing) * tickSpacing,
            tickUpper: (TickMath.MAX_TICK / tickSpacing) * tickSpacing,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: _getAmountWithSlippage(amount0, onSettleParams_.maxSlippage),
            amount1Min: _getAmountWithSlippage(amount1, onSettleParams_.maxSlippage),
            recipient: lotConfiguration[lotId_].recipient,
            deadline: block.timestamp,
            veRamTokenId: onSettleParams_.veRamTokenId
        });
    }
}
