// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Axis callback contracts
import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {Callbacks} from "@axis-core-1.0.0/lib/Callbacks.sol";

// Splits contracts
import {WaterfallModuleFactory} from "@splits-waterfall-1.0.0/WaterfallModuleFactory.sol";
import {WaterfallModule} from "@splits-waterfall-1.0.0/WaterfallModule.sol";

/// @title  FixedFeePayment
/// @notice A callback that makes fixed fee payments to the specified recipients, after which the remaining balance is sent to the last recipient.
/// @dev    This contract uses the Splits Waterfall contract, instead of reproducing the functionality.
contract FixedFeePayment is BaseCallback {
    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_
    ) BaseCallback(auctionHouse_, permissions_) {
        // TODO reject unsupported permissions
    }

    /// @inheritdoc BaseCallback
    function _onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual override {
        // TODO
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented
    function _onCancel(
        uint96,
        uint256,
        bool,
        bytes calldata
    ) internal virtual override {
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented
    function _onCurate(
        uint96,
        uint256,
        bool,
        bytes calldata
    ) internal virtual override {
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    function _onPurchase(
        uint96,
        address,
        uint256,
        uint256,
        bool,
        bytes calldata
    ) internal virtual override {
        // TODO
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented
    function _onBid(
        uint96 ,
        uint64 ,
        address ,
        uint256 ,
        bytes calldata
    ) internal virtual override {
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    function _onSettle(
        uint96 lotId_,
        uint256 proceeds_,
        uint256 refund_,
        bytes calldata callbackData_
    ) internal virtual override {
        // TODO
    }
}
