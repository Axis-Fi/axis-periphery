// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseCallback} from "@axis-core-1.0.4/bases/BaseCallback.sol";
import {Callbacks} from "@axis-core-1.0.4/lib/Callbacks.sol";

/// @notice Generic interface for tokens that implement a balanceOf function (includes ERC-20 and ERC-721)
interface ITokenBalance {
    /// @notice Get the user's token balance
    function balanceOf(
        address user_
    ) external view returns (uint256);
}

/// @title  TokenAllowlist Callback Contract
/// @notice Allowlist contract that checks if a user's balance of a token is above a threshold
/// @dev    This shouldn't be used with liquid, transferable ERC-20s because it can easily be bypassed via flash loans or other swap mechanisms
/// @dev    The intent is to use this with non-transferable tokens (e.g. vote escrow) or illiquid tokens that are not as easily manipulated, e.g. community NFTs
contract TokenAllowlist is BaseCallback {
    // ========== ERRORS ========== //

    // ========== STATE VARIABLES ========== //

    struct TokenCheck {
        ITokenBalance token;
        uint256 threshold;
    }

    /// @notice Stores the token and balance threshold for each lot
    mapping(uint96 lotId => TokenCheck) public lotChecks;

    // ========== CONSTRUCTOR ========== //

    // PERMISSIONS
    // onCreate: true
    // onCancel: false
    // onCurate: false
    // onPurchase: true
    // onBid: true
    // onSettle: false
    // receiveQuoteTokens: false
    // sendBaseTokens: false
    // Contract prefix should be: 10011000 = 0x98

    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_
    ) BaseCallback(auctionHouse_, permissions_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseCallback
    /// @dev        This function reverts if:
    ///             - `callbackData_` is not of the correct length
    ///             - The token contract is not a contract
    ///             - The token contract does not have an ERC20 balanceOf function
    ///
    /// @param      callbackData_    abi-encoded data: (ITokenBalance, uint96) representing the token contract and balance threshold
    function _onCreate(
        uint96 lotId_,
        address,
        address,
        address,
        uint256,
        bool,
        bytes calldata callbackData_
    ) internal override {
        // Check that the parameters are of the correct length
        if (callbackData_.length != 64) {
            revert Callback_InvalidParams();
        }

        // Decode the params to get the token contract and balance threshold
        (ITokenBalance token, uint96 threshold) = abi.decode(callbackData_, (ITokenBalance, uint96));

        // Token must be a contract
        if (address(token).code.length == 0) revert Callback_InvalidParams();

        // Try to get balance for token, revert if it fails
        try token.balanceOf(address(this)) returns (uint256) {}
        catch {
            revert Callback_InvalidParams();
        }

        // Set the lot check
        lotChecks[lotId_] = TokenCheck(token, threshold);
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented
    function _onCancel(uint96, uint256, bool, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented
    function _onCurate(uint96, uint256, bool, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    /// @dev        This function reverts if:
    ///             - The buyer's balance is below the threshold
    function _onPurchase(
        uint96 lotId_,
        address buyer_,
        uint256,
        uint256,
        bool,
        bytes calldata
    ) internal view override {
        _canParticipate(lotId_, buyer_);
    }

    /// @inheritdoc BaseCallback
    /// @dev        This function reverts if:
    ///             - The buyer's balance is below the threshold
    function _onBid(
        uint96 lotId_,
        uint64,
        address buyer_,
        uint256,
        bytes calldata
    ) internal view override {
        _canParticipate(lotId_, buyer_);
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented
    function _onSettle(uint96, uint256, uint256, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _canParticipate(uint96 lotId_, address buyer_) internal view {
        // Get the token check
        TokenCheck memory check = lotChecks[lotId_];

        // Check if the buyer's balance is above the threshold
        if (check.token.balanceOf(buyer_) < check.threshold) revert Callback_NotAuthorized();
    }
}
