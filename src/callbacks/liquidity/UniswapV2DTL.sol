// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.7.0/utils/SafeTransferLib.sol";

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
    using SafeTransferLib for ERC20;

    // ========== STRUCTS ========== //

    /// @notice     Parameters for the onSettle callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      maxSlippage             The maximum slippage allowed when adding liquidity (in terms of `ONE_HUNDRED_PERCENT`)
    struct OnSettleParams {
        uint24 maxSlippage;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The Uniswap V2 factory
    /// @dev        This contract is used to create Uniswap V2 pools
    IUniswapV2Factory public uniV2Factory;

    /// @notice     The Uniswap V2 router
    /// @dev        This contract is used to add liquidity to Uniswap V2 pools
    IUniswapV2Router02 public uniV2Router;

    /// @notice     Mapping of lot ID to pool token
    /// @dev        This is used to track the pool token for each lot
    mapping(uint96 lotId => address poolToken) public lotIdToPoolToken;

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
    ///             - The pool for the token combination already exists
    function __onCreate(
        uint96,
        address,
        address baseToken_,
        address quoteToken_,
        uint256,
        bool,
        bytes calldata
    ) internal virtual override {
        // Check that the pool does not exist
        if (uniV2Factory.getPair(baseToken_, quoteToken_) != address(0)) {
            revert Callback_Params_PoolExists();
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
        bytes memory callbackData_
    ) internal virtual override {
        // Decode the callback data
        OnSettleParams memory params = abi.decode(callbackData_, (OnSettleParams));

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

        // Store the pool token for later
        lotIdToPoolToken[lotId_] = pairAddress;
    }

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function implements the following:
    ///             - If LinearVesting is enabled, mints derivative tokens
    ///             - Otherwise, transfers the pool tokens to the recipient
    function _transferPoolToken(uint96 lotId_) internal virtual override {
        address poolTokenAddress = lotIdToPoolToken[lotId_];
        if (poolTokenAddress == address(0)) {
            revert Callback_PoolTokenNotFound();
        }

        ERC20 poolToken = ERC20(poolTokenAddress);
        uint256 poolTokenQuantity = poolToken.balanceOf(address(this));
        DTLConfiguration memory config = lotConfiguration[lotId_];

        // If vesting is enabled, create the vesting tokens
        if (address(config.linearVestingModule) != address(0)) {
            _mintVestingTokens(
                poolToken,
                poolTokenQuantity,
                config.linearVestingModule,
                config.recipient,
                config.vestingStart,
                config.vestingExpiry
            );
        }
        // Otherwise, send the LP tokens to the seller
        else {
            poolToken.safeTransfer(config.recipient, poolTokenQuantity);
        }
    }
}
