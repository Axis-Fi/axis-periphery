// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Callbacks
import {BaseDirectToLiquidity} from "../BaseDTL.sol";

// Ramses
import {IRamsesV2Factory} from "./lib/IRamsesV2Factory.sol";
import {IRamsesV2PositionManager} from "./lib/IRamsesV2PositionManager.sol";

contract RamsesV2DirectToLiquidity is BaseDirectToLiquidity {
    // ========== STRUCTS ========== //

    /// @notice     Parameters for the onSettle callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      maxSlippage             The maximum slippage allowed when adding liquidity (in terms of `ONE_HUNDRED_PERCENT`)
    struct OnSettleParams {
        uint24 maxSlippage;
    }

    // ========== STATE VARIABLES ========== //

    IRamsesV2Factory public ramsesV2Factory;

    IRamsesV2PositionManager public ramsesV2PositionManager;

    mapping(uint96 => uint256 tokenId) public lotIdToTokenId;

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
    /// @dev        This function implements the following:
    ///             - Validates the parameters
    ///
    ///             This function reverts if:
    ///             - The pool for the token combination already exists
    function __onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual override {
        // Check whether a pool exists for the token combination
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
        // Use the position manager to mint the pool token

        // Add liquidity to the pool
    }

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function implements the following:
    ///             - Transfers the pool token to the recipient
    function _transferPoolToken(uint96 lotId_) internal virtual override {
        uint256 tokenId = lotIdToTokenId[lotId_];
        if (tokenId == 0) {
            revert Callback_PoolTokenNotFound();
        }

        // Use the position manager to transfer the token to the recipient
    }
}
