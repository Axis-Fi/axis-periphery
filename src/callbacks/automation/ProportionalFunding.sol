// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BaseCallback} from "@axis-core-1.0.1/bases/BaseCallback.sol";
import {Callbacks} from "@axis-core-1.0.1/lib/Callbacks.sol";

import {Owned} from "@solmate-6.7.0/auth/Owned.sol";
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";

contract MintableERC20 is ERC20 {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Axis callback contract that allocates tokens to a designated address based on the amount of a tokens.
contract ProportionalFunding is BaseCallback, Owned {

    // Requirements
    // [X] Mint additional tokens to a designated address based on the amount of tokens sold
    // [X] Allow for multiple auctions with different tokens in the same contract to avoid redeployments
    // [X] Require that the owner creates the auctions to avoid unauthorized auctions

    // ========== DATA STRUCTURES ========== //

    struct CreateData {
        address treasury; // receives the proportional funding
        address recipient; // receives the auction proceeds
        uint48 proportion; // percent in basis points of tokens to send to the treasury, e.g. 100 = 1%
    }

    struct FundData {
        address treasury; // receives the proportional funding
        address recipient; // receives the auction proceeds
        uint48 proportion; // percent in basis points of tokens to send to the treasury, e.g. 100 = 1%
        MintableERC20 baseToken; // token to send
        ERC20 quoteToken; // token to receive
    }

    // ========== STATE VARIABLES ========== //

    uint48 internal constant ONE_HUNDRED_PERCENT = 100_00;

    mapping(uint96 lotId => FundData) public lotFundData;

    // ========== CONSTRUCTOR ========== //

    // PERMISSIONS
    // onCreate: true
    // onCancel: false
    // onCurate: false
    // onPurchase: true
    // onBid: false
    // onSettle: false
    // receiveQuoteTokens: true
    // sendBaseTokens: true
    // Contract prefix should be: 10010011 = 0x93

    constructor(
        address atomicAuctionHouse_,
        address owner_
    ) BaseCallback(atomicAuctionHouse_, Callbacks.Permissions({
        onCreate: true,
        onCancel: false,
        onCurate: false,
        onPurchase: true,
        onBid: false,
        onSettle: false,
        receiveQuoteTokens: true,
        sendBaseTokens: true
    })) Owned(owner_) {}

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseCallback
    function _onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256,
        bool prefund_,
        bytes calldata callbackData_
    ) internal override {
        // Validate that the seller is the owner of this contract
        if (seller_ != owner) revert UnauthorizedSeller(owner, seller_);

        // Validate that the auction is not prefunded
        if (prefund_) revert InvalidParam("prefund_");
            
        // Decode the create data from the callback data
        CreateData memory createData = abi.decode(callbackData_, (CreateData));

        // Validate the proportion is greater than 0
        if (createData.proportion == 0) revert InvalidParam("createData.proportion");

        // Validate that the addresses are not zero
        if (createData.treasury == address(0)) revert InvalidParam("createData.treasury");
        if (createData.recipient == address(0)) revert InvalidParam("createData.recipient");

        // Create and store the fund data
        lotFundData[lotId_] = FundData({
            treasury: createData.treasury,
            recipient: createData.recipient,
            proportion: createData.proportion,
            baseToken: MintableERC20(baseToken_),
            quoteToken: ERC20(quoteToken_)
        });
    }

    /// @notice Not implemented for this callback
    function _onCancel(uint96, uint256, bool, bytes memory) internal pure override {
        revert Callback_NotImplemented();
    }

    /// @notice Not implemented for this callback
    function _onCurate(uint96, uint256, bool, bytes memory) internal pure override {
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    function _onPurchase(
        uint96 lotId_,
        address, // buyer address not needed
        uint256 amount_,
        uint256 payout_,
        bool prefunded_,
        bytes calldata
    ) internal override {
        // Validate that the auction is not prefunded
        if (prefunded_) revert InvalidParam("prefunded_");

        // Load the fund data
        FundData memory fundData = lotFundData[lotId_];

        // Transfer the proceeds to the recipient address
        // We know that the amount_ is not zero due to checks in the auction house
        fundData.quoteToken.safeTransfer(fundData.recipient, amount_);

        // Calculate the payout amount to send to the treasury
        uint256 treasuryPayout = payout_ * fundData.proportion / ONE_HUNDRED_PERCENT;

        // Transfer the proportional funding to the treasury address
        fundData.baseToken.mint(fundData.treasury, treasuryPayout);

        // Send the payout to the auction house
        fundData.baseToken.mint(msg.sender, payout_);
    }

    /// @notice Not implemented for this callback
    function _onBid(uint96, uint64, address, uint256, bytes memory) internal pure override {
        revert Callback_NotImplemented();
    }

    /// @notice Not implemented for this callback
    function _onSettle(uint96, uint256, uint256, bytes memory) internal pure override {
        revert Callback_NotImplemented();
    }

}