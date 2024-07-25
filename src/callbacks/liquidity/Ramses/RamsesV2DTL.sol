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
import {IVotingEscrow} from "./lib/IVotingEscrow.sol";

// Uniswap
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";
import {SqrtPriceMath} from "../../../lib/uniswap-v3/SqrtPriceMath.sol";

/// @title      RamsesV2DirectToLiquidity
/// @notice     This Callback contract deposits the proceeds from a batch auction into a Ramses V2 pool
///             in order to create full-range liquidity immediately.
///
///             The LP tokens are transferred to `DTLConfiguration.recipient`, which must be an EOA or a contract that can receive ERC721 tokens.
///
///             An important risk to consider: if the auction's base token is available and liquid, a third-party
///             could front-run the auction by creating the pool before the auction ends. This would allow them to
///             manipulate the price of the pool and potentially profit from the eventual deposit of the auction proceeds.
///
/// @dev        As a general rule, this callback contract does not retain balances of tokens between calls.
///             Transfers are performed within the same function that requires the balance.
contract RamsesV2DirectToLiquidity is BaseDirectToLiquidity {
    // ========== ERRORS ========== //

    error Callback_Params_PoolFeeNotEnabled();

    // ========== STRUCTS ========== //

    /// @notice     Parameters for the onCreate callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      maxSlippage     The maximum slippage allowed when adding liquidity (in terms of basis points, where 1% = 1e2)
    /// @param      veRamTokenId    The token ID of the veRAM token to use for the position (optional)
    struct RamsesV2OnCreateParams {
        uint24 poolFee;
        uint24 maxSlippage;
        uint256 veRamTokenId;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The Ramses V2 factory
    IRamsesV2Factory public ramsesV2Factory;

    /// @notice     The Ramses V2 position manager
    IRamsesV2PositionManager public ramsesV2PositionManager;

    /// @notice     Mapping of lot ID to configuration parameters
    mapping(uint96 => RamsesV2OnCreateParams) public lotParameters;

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
    ///             - `RamsesV1OnCreateParams.poolFee` is not enabled
    ///             - `RamsesV1OnCreateParams.maxSlippage` is out of bounds
    ///             - This contract does not have permission to use the veRamTokenId
    function __onCreate(
        uint96 lotId_,
        address,
        address,
        address,
        uint256,
        bool,
        bytes calldata callbackData_
    ) internal virtual override {
        RamsesV2OnCreateParams memory params;
        {
            OnCreateParams memory onCreateParams = abi.decode(callbackData_, (OnCreateParams));

            // Validate that the callback data is of the correct length
            if (onCreateParams.implParams.length != 96) {
                revert Callback_InvalidParams();
            }

            // Decode the callback data
            params = abi.decode(onCreateParams.implParams, (RamsesV2OnCreateParams));
        }

        // Validate the parameters
        // Pool fee
        // Fee not enabled
        if (ramsesV2Factory.feeAmountTickSpacing(params.poolFee) == 0) {
            revert Callback_Params_PoolFeeNotEnabled();
        }

        // Check that the maxSlippage is in bounds
        // The maxSlippage is stored during onCreate, as the callback data is passed in by the auction seller.
        // As AuctionHouse.settle() can be called by anyone, a value for maxSlippage could be passed that would result in a loss for the auction seller.
        if (params.maxSlippage > ONE_HUNDRED_PERCENT) {
            revert Callback_Params_PercentOutOfBounds(params.maxSlippage, 0, ONE_HUNDRED_PERCENT);
        }

        // Check that the callback has been given permission to use the veRamTokenId
        if (
            params.veRamTokenId > 0
                && !IVotingEscrow(ramsesV2PositionManager.veRam()).isApprovedOrOwner(
                    address(this), params.veRamTokenId
                )
        ) {
            revert Callback_InvalidParams();
        }

        lotParameters[lotId_] = params;
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
        bytes memory
    ) internal virtual override {
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
                lotParameters[lotId_].poolFee,
                sqrtPriceX96
            );
        }

        // Mint the position and add liquidity
        {
            IRamsesV2PositionManager.MintParams memory mintParams =
                _getMintParams(lotId_, quoteToken_, quoteTokenAmount_, baseToken_, baseTokenAmount_);

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
        uint256 baseTokenAmount_
    ) internal view returns (IRamsesV2PositionManager.MintParams memory) {
        RamsesV2OnCreateParams memory params = lotParameters[lotId_];

        int24 tickSpacing = ramsesV2Factory.feeAmountTickSpacing(params.poolFee);

        // Determine the ordering of tokens
        bool quoteTokenIsToken0 = quoteToken_ < baseToken_;

        // Calculate the minimum amount out for each token
        uint256 amount0 = quoteTokenIsToken0 ? quoteTokenAmount_ : baseTokenAmount_;
        uint256 amount1 = quoteTokenIsToken0 ? baseTokenAmount_ : quoteTokenAmount_;

        return IRamsesV2PositionManager.MintParams({
            token0: quoteTokenIsToken0 ? quoteToken_ : baseToken_,
            token1: quoteTokenIsToken0 ? baseToken_ : quoteToken_,
            fee: params.poolFee,
            tickLower: (TickMath.MIN_TICK / tickSpacing) * tickSpacing,
            tickUpper: (TickMath.MAX_TICK / tickSpacing) * tickSpacing,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: _getAmountWithSlippage(amount0, params.maxSlippage),
            amount1Min: _getAmountWithSlippage(amount1, params.maxSlippage),
            recipient: lotConfiguration[lotId_].recipient,
            deadline: block.timestamp,
            veRamTokenId: params.veRamTokenId
        });
    }
}
