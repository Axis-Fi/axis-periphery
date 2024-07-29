// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";

// Callbacks
import {BaseDirectToLiquidity} from "../BaseDTL.sol";

// Cleopatra
import {ICleopatraV2Pool} from "./lib/ICleopatraV2Pool.sol";
import {ICleopatraV2Factory} from "./lib/ICleopatraV2Factory.sol";
import {ICleopatraV2PositionManager} from "./lib/ICleopatraV2PositionManager.sol";

// Uniswap
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";
import {SqrtPriceMath} from "../../../lib/uniswap-v3/SqrtPriceMath.sol";

/// @title      CleopatraV2DirectToLiquidity
/// @notice     This Callback contract deposits the proceeds from a batch auction into a Cleopatra V2 pool
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
contract CleopatraV2DirectToLiquidity is BaseDirectToLiquidity {
    // ========== ERRORS ========== //

    /// @notice The specified pool fee is not enabled in the Cleopatra V2 Factory
    error Callback_Params_PoolFeeNotEnabled();

    // ========== STRUCTS ========== //

    /// @notice     Parameters for the onCreate callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      maxSlippage     The maximum slippage allowed when adding liquidity (in terms of basis points, where 1% = 1e2)
    struct CleopatraV2OnCreateParams {
        uint24 poolFee;
        uint24 maxSlippage;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The Cleopatra V2 factory
    ICleopatraV2Factory public cleopatraV2Factory;

    /// @notice     The Cleopatra V2 position manager
    ICleopatraV2PositionManager public cleopatraV2PositionManager;

    /// @notice     Mapping of lot ID to Cleopatra V2 token ID
    mapping(uint96 => uint256) public lotIdToTokenId;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address cleopatraV2Factory_,
        address payable cleopatraV2PositionManager_
    ) BaseDirectToLiquidity(auctionHouse_) {
        if (cleopatraV2Factory_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        cleopatraV2Factory = ICleopatraV2Factory(cleopatraV2Factory_);

        if (cleopatraV2PositionManager_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        cleopatraV2PositionManager = ICleopatraV2PositionManager(cleopatraV2PositionManager_);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function performs the following:
    ///             - Validates the input data
    ///
    ///             This function reverts if:
    ///             - `CleopatraV2OnCreateParams.poolFee` is not enabled
    ///             - `CleopatraV2OnCreateParams.maxSlippage` is out of bounds
    function __onCreate(
        uint96 lotId_,
        address,
        address,
        address,
        uint256,
        bool,
        bytes calldata
    ) internal virtual override {
        CleopatraV2OnCreateParams memory params = _decodeParameters(lotId_);

        // Validate the parameters
        // Pool fee
        // Fee not enabled
        if (cleopatraV2Factory.feeAmountTickSpacing(params.poolFee) == 0) {
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
                _decodeParameters(lotId_).poolFee,
                sqrtPriceX96
            );
        }

        // Mint the position and add liquidity
        {
            ICleopatraV2PositionManager.MintParams memory mintParams =
                _getMintParams(lotId_, quoteToken_, quoteTokenAmount_, baseToken_, baseTokenAmount_);

            // Approve spending
            ERC20(quoteToken_).approve(address(cleopatraV2PositionManager), quoteTokenAmount_);
            ERC20(baseToken_).approve(address(cleopatraV2PositionManager), baseTokenAmount_);

            // Mint the position
            (uint256 tokenId,,,) = cleopatraV2PositionManager.mint(mintParams);
            lotIdToTokenId[lotId_] = tokenId;

            // Reset dangling approvals
            // The position manager may not spend all tokens
            ERC20(quoteToken_).approve(address(cleopatraV2PositionManager), 0);
            ERC20(baseToken_).approve(address(cleopatraV2PositionManager), 0);
        }
    }

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function does not perform any actions,
    ///             as `_mintAndDeposit()` directly transfers the token to the recipient
    function _transferPoolToken(uint96) internal virtual override {
        // Nothing to do
    }

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This implementation disables linear vesting
    function _isLinearVestingSupported() internal pure virtual override returns (bool) {
        return false;
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
        pool = cleopatraV2Factory.getPool(token0, token1, fee);

        if (pool == address(0)) {
            pool = cleopatraV2Factory.createPool(token0, token1, fee, sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing,,,,,,) = ICleopatraV2Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                ICleopatraV2Pool(pool).initialize(sqrtPriceX96);
            }
        }
    }

    function _getMintParams(
        uint96 lotId_,
        address quoteToken_,
        uint256 quoteTokenAmount_,
        address baseToken_,
        uint256 baseTokenAmount_
    ) internal view returns (ICleopatraV2PositionManager.MintParams memory) {
        CleopatraV2OnCreateParams memory params = _decodeParameters(lotId_);

        int24 tickSpacing = cleopatraV2Factory.feeAmountTickSpacing(params.poolFee);

        // Determine the ordering of tokens
        bool quoteTokenIsToken0 = quoteToken_ < baseToken_;

        // Calculate the minimum amount out for each token
        uint256 amount0 = quoteTokenIsToken0 ? quoteTokenAmount_ : baseTokenAmount_;
        uint256 amount1 = quoteTokenIsToken0 ? baseTokenAmount_ : quoteTokenAmount_;

        return ICleopatraV2PositionManager.MintParams({
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
            veNFTTokenId: 0 // Not supported at the moment
        });
    }

    /// @notice Decodes the configuration parameters from the DTLConfiguration
    /// @dev   The configuration parameters are stored in `DTLConfiguration.implParams`
    function _decodeParameters(uint96 lotId_)
        internal
        view
        returns (CleopatraV2OnCreateParams memory)
    {
        DTLConfiguration memory lotConfig = lotConfiguration[lotId_];
        // Validate that the callback data is of the correct length
        if (lotConfig.implParams.length != 64) {
            revert Callback_InvalidParams();
        }

        return abi.decode(lotConfig.implParams, (CleopatraV2OnCreateParams));
    }
}
