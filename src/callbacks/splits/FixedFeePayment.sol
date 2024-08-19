// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.7.0/utils/SafeTransferLib.sol";

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
    using SafeTransferLib for ERC20;

    // ========== ERRORS ========== //

    // ========== DATA STRUCTURES ========== //

    /// @notice Parameters for the WaterfallModule contract
    /// @param  recipients  Addresses to waterfall payments to. The array should be one longer than `thresholds`, as residual payments are sent to the last recipient
    /// @param  thresholds  Absolute payment thresholds for waterfall recipients
    struct WaterfallParams {
        address[] recipients;
        uint256[] thresholds;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice The factory contract for deploying WaterfallModule clones
    WaterfallModuleFactory public immutable factory;

    /// @notice Stores the WaterfallModule contract for each lot
    mapping(uint96 lotId => WaterfallModule) public lotModules;

    /// @notice Stores the quote token for each lot
    mapping(uint96 lotId => ERC20) public lotQuoteTokens;

    // ========== CONSTRUCTOR ========== //

    /// @dev This function reverts if:
    ///      - An unsupported permission is specified
    ///      - The callback is not configured to receive quote tokens
    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_,
        address factory_
    ) BaseCallback(auctionHouse_, permissions_) {
        // Validate that no unsupported permissions are specified
        if (permissions_.onCancel || permissions_.onCurate || permissions_.onBid) {
            revert Callback_InvalidParams();
        }

        // Validate that the callback is configured to receive proceeds
        if (!permissions_.receiveQuoteTokens) {
            revert Callback_InvalidParams();
        }

        // Validate that the factory contract is not the zero address
        if (factory_ == address(0)) {
            revert Callback_InvalidParams();
        }

        // Set the factory contract
        factory = WaterfallModuleFactory(factory_);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseCallback
    /// @dev        This function performs the following:
    ///             - Validates the configuration parameters
    ///             - Creates a new Splits Waterfall contract
    ///
    ///             This function reverts if:
    ///             - A Splits contract already exists for the lot
    ///             - The callback data cannot be decoded into a WaterfallParams struct
    ///             - Validation of the parameters by WaterfallModuleFactory fails
    ///
    ///             Notes:
    ///             - The Splits Waterfall contract supports a fallback address for any other tokens that are sent to the contract. This is set to the seller's address.
    function _onCreate(
        uint96 lotId_,
        address seller_,
        address,
        address quoteToken_,
        uint256,
        bool,
        bytes calldata callbackData_
    ) internal virtual override {
        // Validate if the Splits contract already exists for the lot
        if (lotModules[lotId_] != WaterfallModule(address(0))) {
            revert Callback_InvalidParams();
        }

        // Decode the callback data
        WaterfallParams memory params = abi.decode(callbackData_, (WaterfallParams));

        // Create the WaterfallModule
        WaterfallModule wm = factory.createWaterfallModule(
            quoteToken_, seller_, params.recipients, params.thresholds
        );

        // Store configuration
        lotModules[lotId_] = wm;
        lotQuoteTokens[lotId_] = ERC20(quoteToken_);
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented
    function _onCancel(uint96, uint256, bool, bytes calldata) internal virtual override {
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented
    function _onCurate(uint96, uint256, bool, bytes calldata) internal virtual override {
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    /// @dev        This function performs the following:
    ///             - Performs validation
    ///             - Transfers the proceeds to the Splits contract
    ///             - Calls the Splits contract to allocate the tokens to the recipients
    ///
    ///             This function reverts if:
    ///             - The Splits contract for the lot does not exist
    ///
    ///             Notes:
    ///             - The `WaterfallModule.waterfallFundsPull()` function is called to allocate the tokens to the recipients but not transfer them. This is to avoid errors.
    ///             - Funds can be withdrawn by calling `WaterfallModule.withdraw()` on the Splits contract.
    function _onPurchase(
        uint96 lotId_,
        address,
        uint256 amount_,
        uint256,
        bool,
        bytes calldata
    ) internal virtual override hasModule(lotId_) {
        WaterfallModule wm = lotModules[lotId_];

        // Transfer to the Splits contract
        lotQuoteTokens[lotId_].safeTransfer(address(wm), amount_);

        // Allocate tokens
        wm.waterfallFundsPull();
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented
    function _onBid(uint96, uint64, address, uint256, bytes calldata) internal virtual override {
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    /// @dev        This function performs the following:
    ///             - Performs validation
    ///             - Transfers the proceeds to the Splits contract
    ///             - Calls the Splits contract to allocate the tokens to the recipients
    ///
    ///             This function reverts if:
    ///             - The Splits contract for the lot does not exist
    ///
    ///             Notes:
    ///             - The `WaterfallModule.waterfallFundsPull()` function is called to allocate the tokens to the recipients but not transfer them. This is to avoid errors.
    ///             - Funds can be withdrawn by calling `WaterfallModule.withdraw()` on the Splits contract.
    function _onSettle(
        uint96 lotId_,
        uint256 proceeds_,
        uint256,
        bytes calldata
    ) internal virtual override hasModule(lotId_) {
        // Transfer to the Splits contract
        lotQuoteTokens[lotId_].safeTransfer(address(lotModules[lotId_]), proceeds_);

        // Allocate tokens
        lotModules[lotId_].waterfallFundsPull();
    }

    // ========== MODIFIERS ========== //

    /// @notice Modifier to check if a WaterfallModule exists for the lot
    modifier hasModule(uint96 lotId_) {
        // Validate the module
        if (lotModules[lotId_] == WaterfallModule(address(0))) {
            revert Callback_InvalidParams();
        }

        // Validate the quote token
        if (lotQuoteTokens[lotId_] == ERC20(address(0))) {
            revert Callback_InvalidParams();
        }
        _;
    }
}
