// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";

// Callbacks
import {BaseDirectToLiquidity} from "../BaseDTL.sol";

// Ramses
import {IRamsesV1Factory} from "./lib/IRamsesV1Factory.sol";
import {IRamsesV1Router} from "./lib/IRamsesV1Router.sol";

/// @title      RamsesV1DirectToLiquidity
/// @notice     This Callback contract deposits the proceeds from a batch auction into a Ramses V1 pool
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
contract RamsesV1DirectToLiquidity is BaseDirectToLiquidity {
    // ========== STRUCTS ========== //

    /// @notice     Parameters for the onCreate callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      stable          Whether the pool is stable or volatile
    struct RamsesV1OnCreateParams {
        bool stable;
    }

    /// @notice     Parameters for the onSettle callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      maxSlippage     The maximum slippage allowed when adding liquidity (in terms of `ONE_HUNDRED_PERCENT`)
    struct RamsesV1OnSettleParams {
        uint24 maxSlippage;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The Ramses PairFactory contract
    /// @dev        This contract is used to create Ramses pairs
    IRamsesV1Factory public pairFactory;

    /// @notice     The Ramses Router contract
    /// @dev        This contract is used to add liquidity to Ramses pairs
    IRamsesV1Router public router;

    /// @notice     Records whether a pool should be stable or volatile
    mapping(uint96 => bool) public lotIdToStable;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address pairFactory_,
        address payable router_
    ) BaseDirectToLiquidity(auctionHouse_) {
        if (pairFactory_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        if (router_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        pairFactory = IRamsesV1Factory(pairFactory_);
        router = IRamsesV1Router(router_);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function implements the following:
    ///             - Validates the parameters
    ///
    ///             This function reverts if:
    ///             - The pool for the token combination already exists
    function __onCreate(
        uint96 lotId_,
        address,
        address baseToken_,
        address quoteToken_,
        uint256,
        bool,
        bytes calldata callbackData_
    ) internal virtual override {
        // Decode the callback data
        RamsesV1OnCreateParams memory params = abi.decode(callbackData_, (RamsesV1OnCreateParams));

        // Check that the pool does not exist
        if (pairFactory.getPair(baseToken_, quoteToken_, params.stable) != address(0)) {
            revert Callback_Params_PoolExists();
        }

        // Record whether the pool should be stable or volatile
        lotIdToStable[lotId_] = params.stable;
    }

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function implements the following:
    ///             - Validates the parameters
    ///             - Creates the pool if necessary
    ///             - Deposits the tokens into the pool
    function _mintAndDeposit(
        uint96 lotId_,
        address quoteToken_,
        uint256 quoteTokenAmount_,
        address baseToken_,
        uint256 baseTokenAmount_,
        bytes memory callbackData_
    ) internal virtual override returns (ERC20 poolToken) {
        // Decode the callback data
        RamsesV1OnSettleParams memory params = abi.decode(callbackData_, (RamsesV1OnSettleParams));

        // Create and initialize the pool if necessary
        // Token orientation is irrelevant
        bool stable = lotIdToStable[lotId_];
        address pairAddress = pairFactory.getPair(baseToken_, quoteToken_, stable);
        if (pairAddress == address(0)) {
            pairAddress = pairFactory.createPair(baseToken_, quoteToken_, stable);
        }

        // Calculate the minimum amount out for each token
        uint256 quoteTokenAmountMin = _getAmountWithSlippage(quoteTokenAmount_, params.maxSlippage);
        uint256 baseTokenAmountMin = _getAmountWithSlippage(baseTokenAmount_, params.maxSlippage);

        // Approve the router to spend the tokens
        ERC20(quoteToken_).approve(address(router), quoteTokenAmount_);
        ERC20(baseToken_).approve(address(router), baseTokenAmount_);

        // Deposit into the pool
        // Token orientation is irrelevant
        router.addLiquidity(
            quoteToken_,
            baseToken_,
            stable,
            quoteTokenAmount_,
            baseTokenAmount_,
            quoteTokenAmountMin,
            baseTokenAmountMin,
            address(this),
            block.timestamp
        );

        // Remove any dangling approvals
        // This is necessary, since the router may not spend all available tokens
        ERC20(quoteToken_).approve(address(router), 0);
        ERC20(baseToken_).approve(address(router), 0);

        return ERC20(pairAddress);
    }
}
