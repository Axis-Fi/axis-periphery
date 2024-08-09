// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";

// Uniswap
import {IUniswapV2Factory} from "@uniswap-v2-core-1.0.1/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap-v2-periphery-1.0.1/interfaces/IUniswapV2Router02.sol";

// Callbacks
import {BaseDirectToLiquidity} from "./BaseDTL.sol";

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

        // Calculate the minimum amount out for each token
        uint256 quoteTokenAmountMin = _getAmountWithSlippage(quoteTokenAmount_, params.maxSlippage);
        uint256 baseTokenAmountMin = _getAmountWithSlippage(baseTokenAmount_, params.maxSlippage);

        // Approve the router to spend the tokens
        ERC20(quoteToken_).approve(address(uniV2Router), quoteTokenAmount_);
        ERC20(baseToken_).approve(address(uniV2Router), baseTokenAmount_);

        // Deposit into the pool
        uniV2Router.addLiquidity(
            quoteToken_,
            baseToken_,
            quoteTokenAmount_,
            baseTokenAmount_,
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
