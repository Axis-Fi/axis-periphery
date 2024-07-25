// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.7.0/utils/SafeTransferLib.sol";

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
    using SafeTransferLib for ERC20;

    // ========== STRUCTS ========== //

    /// @notice     Parameters for the onCreate callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      stable          Whether the pool will be stable or volatile
    /// @param      maxSlippage     The maximum slippage allowed when adding liquidity (in terms of basis points, where 1% = 1e2)
    struct RamsesV1OnCreateParams {
        bool stable;
        uint24 maxSlippage;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The Ramses PairFactory contract
    /// @dev        This contract is used to create Ramses pairs
    IRamsesV1Factory public pairFactory;

    /// @notice     The Ramses Router contract
    /// @dev        This contract is used to add liquidity to Ramses pairs
    IRamsesV1Router public router;

    /// @notice     Mapping of lot ID to pool token
    mapping(uint96 => address) public lotIdToPoolToken;

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
    ///             - The callback data is of the incorrect length
    ///             - `RamsesV1OnCreateParams.maxSlippage` is out of bounds
    function __onCreate(
        uint96 lotId_,
        address,
        address,
        address,
        uint256,
        bool,
        bytes calldata
    ) internal virtual override {
        RamsesV1OnCreateParams memory params = _decodeParameters(lotId_);

        // Check that the slippage amount is within bounds
        // The maxSlippage is stored during onCreate, as the callback data is passed in by the auction seller.
        // As AuctionHouse.settle() can be called by anyone, a value for maxSlippage could be passed that would result in a loss for the auction seller.
        if (params.maxSlippage > ONE_HUNDRED_PERCENT) {
            revert Callback_Params_PercentOutOfBounds(params.maxSlippage, 0, ONE_HUNDRED_PERCENT);
        }
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
        bytes memory
    ) internal virtual override {
        RamsesV1OnCreateParams memory params = _decodeParameters(lotId_);

        // Create and initialize the pool if necessary
        // Token orientation is irrelevant
        address pairAddress = pairFactory.getPair(baseToken_, quoteToken_, params.stable);
        if (pairAddress == address(0)) {
            pairAddress = pairFactory.createPair(baseToken_, quoteToken_, params.stable);
        }

        // Calculate the minimum amount out for each token
        uint256 quoteTokenAmountMin = _getAmountWithSlippage(quoteTokenAmount_, params.maxSlippage);
        uint256 baseTokenAmountMin = _getAmountWithSlippage(baseTokenAmount_, params.maxSlippage);

        // Approve the router to spend the tokens
        ERC20(quoteToken_).approve(address(router), quoteTokenAmount_);
        ERC20(baseToken_).approve(address(router), baseTokenAmount_);

        // Deposit into the pool
        // Token orientation is irrelevant
        // If the pool is liquid and initialised at a price different to the auction, this will revert
        // The auction would fail to settle, and bidders could be refunded by an abort() call
        router.addLiquidity(
            quoteToken_,
            baseToken_,
            params.stable,
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

    function _decodeParameters(uint96 lotId_)
        internal
        view
        returns (RamsesV1OnCreateParams memory)
    {
        DTLConfiguration memory lotConfig = lotConfiguration[lotId_];
        // Validate that the callback data is of the correct length
        if (lotConfig.implParams.length != 64) {
            revert Callback_InvalidParams();
        }

        return abi.decode(lotConfig.implParams, (RamsesV1OnCreateParams));
    }
}
