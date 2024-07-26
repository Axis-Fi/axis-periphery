// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate-6.7.0/utils/SafeTransferLib.sol";

// Callbacks
import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {Callbacks} from "@axis-core-1.0.0/lib/Callbacks.sol";

// AuctionHouse
import {ILinearVesting} from "@axis-core-1.0.0/interfaces/modules/derivatives/ILinearVesting.sol";
import {LinearVesting} from "@axis-core-1.0.0/modules/derivatives/LinearVesting.sol";
import {AuctionHouse} from "@axis-core-1.0.0/bases/AuctionHouse.sol";
import {Keycode, wrapVeecode} from "@axis-core-1.0.0/modules/Modules.sol";

/// @notice     Base contract for DirectToLiquidity callbacks
/// @dev        This contract is intended to be inherited by a callback contract that supports a particular liquidity platform, such as Uniswap V2 or V3.
///
///             It provides integration points that enable the implementing contract to support different liquidity platforms.
///
///             NOTE: The parameters to the functions in this contract refer to linear vesting, which is currently only supported for ERC20 pool tokens. A future version could improve upon this by shifting the (ERC20) linear vesting functionality into a variant that inherits from this contract.
abstract contract BaseDirectToLiquidity is BaseCallback {
    using SafeTransferLib for ERC20;

    // ========== ERRORS ========== //

    error Callback_InsufficientBalance(
        address token_, address account_, uint256 balance_, uint256 required_
    );

    error Callback_Params_InvalidAddress();

    error Callback_Params_PercentOutOfBounds(uint24 actual_, uint24 min_, uint24 max_);

    error Callback_Params_PoolExists();

    error Callback_Params_InvalidVestingParams();

    error Callback_LinearVestingModuleNotFound();

    error Callback_PoolTokenNotFound();

    /// @notice The auction lot has already been completed
    error Callback_AlreadyComplete();

    // ========== STRUCTS ========== //

    /// @notice     Configuration for the DTL callback
    ///
    /// @param      recipient                   The recipient of the LP tokens
    /// @param      lotCapacity                 The capacity of the lot
    /// @param      lotCuratorPayout            The maximum curator payout of the lot
    /// @param      proceedsUtilisationPercent  The percentage of the proceeds to deposit into the pool, in basis points (1% = 100)
    /// @param      vestingStart                The start of the vesting period for the LP tokens (0 if disabled)
    /// @param      vestingExpiry               The end of the vesting period for the LP tokens (0 if disabled)
    /// @param      linearVestingModule         The LinearVesting module for the LP tokens (only set if linear vesting is enabled)
    /// @param      active                      Whether the lot is active
    /// @param      implParams                  The implementation-specific parameters
    struct DTLConfiguration {
        address recipient;
        uint256 lotCapacity;
        uint256 lotCuratorPayout;
        uint24 proceedsUtilisationPercent;
        uint48 vestingStart;
        uint48 vestingExpiry;
        LinearVesting linearVestingModule;
        bool active;
        bytes implParams;
    }

    /// @notice     Parameters used in the onCreate callback
    ///
    /// @param      proceedsUtilisationPercent   The percentage of the proceeds to use in the pool
    /// @param      vestingStart                 The start of the vesting period for the LP tokens (0 if disabled)
    /// @param      vestingExpiry                The end of the vesting period for the LP tokens (0 if disabled)
    /// @param      recipient                    The recipient of the LP tokens
    /// @param      implParams                   The implementation-specific parameters
    struct OnCreateParams {
        uint24 proceedsUtilisationPercent;
        // TODO ideally move the vesting parameters into an inheriting contract that accesses implParams
        uint48 vestingStart;
        uint48 vestingExpiry;
        address recipient;
        bytes implParams;
    }

    // ========== STATE VARIABLES ========== //

    uint24 public constant ONE_HUNDRED_PERCENT = 100e2;
    bytes5 public constant LINEAR_VESTING_KEYCODE = 0x4c49560000; // "LIV"

    /// @notice     Maps the lot id to the DTL configuration
    mapping(uint96 lotId => DTLConfiguration) public lotConfiguration;

    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_)
        BaseCallback(
            auctionHouse_,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: true,
                onCurate: true,
                onPurchase: false,
                onBid: false,
                onSettle: true,
                receiveQuoteTokens: true,
                sendBaseTokens: false
            })
        )
    {}

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseCallback
    /// @notice     Callback for when a lot is created
    /// @dev        This function performs the following:
    ///             - Validates the input data
    ///             - Calls the Uniswap-specific implementation
    ///             - Stores the configuration for the lot
    ///
    ///             This function reverts if:
    ///             - OnCreateParams.proceedsUtilisationPercent is out of bounds
    ///             - OnCreateParams.vestingStart or OnCreateParams.vestingExpiry do not pass validation
    ///             - Vesting is enabled and the linear vesting module is not found
    ///             - The OnCreateParams.recipient address is the zero address
    ///
    /// @param      lotId_          The lot ID
    /// @param      baseToken_      The base token address
    /// @param      quoteToken_     The quote token address
    /// @param      capacity_       The capacity of the lot
    /// @param      callbackData_   Encoded OnCreateParams struct
    function _onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual override {
        // Decode callback data into the params
        OnCreateParams memory params = abi.decode(callbackData_, (OnCreateParams));

        // Validate the parameters
        // Proceeds utilisation
        if (
            params.proceedsUtilisationPercent == 0
                || params.proceedsUtilisationPercent > ONE_HUNDRED_PERCENT
        ) {
            revert Callback_Params_PercentOutOfBounds(
                params.proceedsUtilisationPercent, 1, ONE_HUNDRED_PERCENT
            );
        }

        // Vesting
        LinearVesting linearVestingModule;

        // If vesting is enabled
        if (params.vestingStart != 0 || params.vestingExpiry != 0) {
            // Get the linear vesting module (or revert)
            linearVestingModule = LinearVesting(_getLatestLinearVestingModule());

            // Validate
            if (
                // We will actually use the LP tokens, but this is a placeholder as we really want to validate the vesting parameters
                !linearVestingModule.validate(
                    address(baseToken_),
                    _getEncodedVestingParams(params.vestingStart, params.vestingExpiry)
                )
            ) {
                revert Callback_Params_InvalidVestingParams();
            }
        }

        // If the recipient is the zero address
        if (params.recipient == address(0)) {
            revert Callback_Params_InvalidAddress();
        }

        // Store the configuration
        lotConfiguration[lotId_] = DTLConfiguration({
            recipient: params.recipient,
            lotCapacity: capacity_,
            lotCuratorPayout: 0,
            proceedsUtilisationPercent: params.proceedsUtilisationPercent,
            vestingStart: params.vestingStart,
            vestingExpiry: params.vestingExpiry,
            linearVestingModule: linearVestingModule,
            active: true,
            implParams: params.implParams
        });

        // Call the Uniswap-specific implementation
        __onCreate(lotId_, seller_, baseToken_, quoteToken_, capacity_, prefund_, callbackData_);
    }

    /// @notice     Uniswap-specific implementation of the onCreate callback
    /// @dev        The implementation will be called by the _onCreate function
    ///             after the `callbackData_` has been validated and after the
    ///             lot configuration is stored.
    ///
    ///             The implementation should perform the following:
    ///             - Additional validation
    ///
    /// @param      lotId_          The lot ID
    /// @param      seller_         The seller address
    /// @param      baseToken_      The base token address
    /// @param      quoteToken_     The quote token address
    /// @param      capacity_       The capacity of the lot
    /// @param      prefund_        Whether the lot is prefunded
    /// @param      callbackData_   Encoded OnCreateParams struct
    function __onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual;

    /// @notice     Callback for when a lot is cancelled
    /// @dev        This function performs the following:
    ///             - Marks the lot as inactive
    ///
    ///             This function reverts if:
    ///             - The lot is not registered
    ///             - The lot has already been completed
    ///
    /// @param      lotId_          The lot ID
    function _onCancel(uint96 lotId_, uint256, bool, bytes calldata) internal override {
        // Check that the lot is active
        if (!lotConfiguration[lotId_].active) {
            revert Callback_AlreadyComplete();
        }

        // Mark the lot as inactive to prevent further actions
        DTLConfiguration storage config = lotConfiguration[lotId_];
        config.active = false;
    }

    /// @notice     Callback for when a lot is curated
    /// @dev        This function performs the following:
    ///             - Records the curator payout
    ///
    ///             This function reverts if:
    ///             - The lot is not registered
    ///             - The lot has already been completed
    ///
    /// @param      lotId_          The lot ID
    /// @param      curatorPayout_  The maximum curator payout
    function _onCurate(
        uint96 lotId_,
        uint256 curatorPayout_,
        bool,
        bytes calldata
    ) internal override {
        // Check that the lot is active
        if (!lotConfiguration[lotId_].active) {
            revert Callback_AlreadyComplete();
        }

        // Update the funding
        DTLConfiguration storage config = lotConfiguration[lotId_];
        config.lotCuratorPayout = curatorPayout_;
    }

    /// @notice     Callback for a purchase
    /// @dev        Not implemented
    function _onPurchase(
        uint96,
        address,
        uint256,
        uint256,
        bool,
        bytes calldata
    ) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    /// @notice     Callback for a bid
    /// @dev        Not implemented
    function _onBid(uint96, uint64, address, uint256, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    /// @notice     Callback for claiming the proceeds
    /// @dev        This function performs the following:
    ///             - Calculates the base and quote tokens to deposit into the pool
    ///             - Calls the Uniswap-specific implementation to mint and deposit into the pool
    ///             - If vesting is enabled, mints the vesting tokens, or transfers the LP tokens to the recipient
    ///             - Sends any remaining quote and base tokens to the seller
    ///
    ///             The assumptions are:
    ///             - the callback has `proceeds_` quantity of quote tokens (as `receiveQuoteTokens` flag is set)
    ///             - the seller has the required balance of base tokens
    ///             - the seller has approved the callback to spend the base tokens
    ///
    ///             This function reverts if:
    ///             - The lot is not registered
    ///             - The lot is already complete
    ///
    /// @param      lotId_          The lot ID
    /// @param      proceeds_       The proceeds from the auction
    /// @param      refund_         The refund from the auction
    /// @param      callbackData_   Implementation-specific data
    function _onSettle(
        uint96 lotId_,
        uint256 proceeds_,
        uint256 refund_,
        bytes calldata callbackData_
    ) internal virtual override {
        DTLConfiguration storage config = lotConfiguration[lotId_];

        // Check that the lot is active
        if (!config.active) {
            revert Callback_AlreadyComplete();
        }

        // Mark the lot as inactive
        lotConfiguration[lotId_].active = false;

        address seller;
        address baseToken;
        address quoteToken;
        {
            (seller, baseToken, quoteToken,,,,,,) = AuctionHouse(AUCTION_HOUSE).lotRouting(lotId_);
        }

        uint256 baseTokensRequired;
        uint256 quoteTokensRequired;
        {
            // Calculate the actual lot capacity that was used
            uint256 capacityUtilised;
            {
                // If curation is enabled, refund_ will also contain the refund on the curator payout. Adjust for that.
                // Example:
                // 100 capacity + 10 curator
                // 90 capacity sold, 9 curator payout
                // 11 refund
                // Utilisation = 1 - 11/110 = 90%
                uint256 utilisationPercent =
                    100e2 - refund_ * 100e2 / (config.lotCapacity + config.lotCuratorPayout);

                capacityUtilised = (config.lotCapacity * utilisationPercent) / ONE_HUNDRED_PERCENT;
            }

            // Calculate the base tokens required to create the pool
            baseTokensRequired =
                _tokensRequiredForPool(capacityUtilised, config.proceedsUtilisationPercent);
            quoteTokensRequired =
                _tokensRequiredForPool(proceeds_, config.proceedsUtilisationPercent);
        }

        // Ensure the required quote tokens are present in this contract before minting
        {
            // Check that sufficient balance exists
            uint256 quoteTokenBalance = ERC20(quoteToken).balanceOf(address(this));
            if (quoteTokenBalance < quoteTokensRequired) {
                revert Callback_InsufficientBalance(
                    quoteToken, address(this), quoteTokensRequired, quoteTokenBalance
                );
            }
        }

        // Ensure the required base tokens are present on the seller address before minting
        {
            // Check that sufficient balance exists
            uint256 baseTokenBalance = ERC20(baseToken).balanceOf(seller);
            if (baseTokenBalance < baseTokensRequired) {
                revert Callback_InsufficientBalance(
                    baseToken, seller, baseTokensRequired, baseTokenBalance
                );
            }

            // Transfer the base tokens from the seller to this contract
            ERC20(baseToken).safeTransferFrom(seller, address(this), baseTokensRequired);
        }

        // Mint and deposit into the pool
        _mintAndDeposit(
            lotId_, quoteToken, quoteTokensRequired, baseToken, baseTokensRequired, callbackData_
        );

        // Transfer the pool token to the recipient
        _transferPoolToken(lotId_);

        // Send any remaining quote tokens to the seller
        {
            uint256 quoteTokenBalance = ERC20(quoteToken).balanceOf(address(this));
            if (quoteTokenBalance > 0) {
                ERC20(quoteToken).safeTransfer(seller, quoteTokenBalance);
            }
        }

        // Send any remaining base tokens to the seller
        {
            uint256 baseTokenBalance = ERC20(baseToken).balanceOf(address(this));
            if (baseTokenBalance > 0) {
                ERC20(baseToken).safeTransfer(seller, baseTokenBalance);
            }
        }
    }

    /// @notice     Mint and deposit into the pool
    /// @dev        This function should be implemented by the Uniswap-specific callback
    ///
    ///             It is expected to:
    ///             - Create and initialize the pool
    ///             - Deposit the quote and base tokens into the pool
    ///             - The pool tokens should be received by this contract
    ///             - Store the details of the pool token (ERC20 or ERC721) in the state
    ///
    /// @param      lotId_              The lot ID
    /// @param      quoteToken_         The quote token address
    /// @param      quoteTokenAmount_   The amount of quote tokens to deposit
    /// @param      baseToken_          The base token address
    /// @param      baseTokenAmount_    The amount of base tokens to deposit
    /// @param      callbackData_       Implementation-specific data
    function _mintAndDeposit(
        uint96 lotId_,
        address quoteToken_,
        uint256 quoteTokenAmount_,
        address baseToken_,
        uint256 baseTokenAmount_,
        bytes memory callbackData_
    ) internal virtual;

    /// @notice    Transfer the pool token to the recipient
    /// @dev       This function should be implemented by the Uniswap-specific callback
    ///
    ///            It is expected to:
    ///            - Transfer the pool token (ERC20 or ERC721) to the recipient
    ///
    /// @param      lotId_          The lot ID
    function _transferPoolToken(uint96 lotId_) internal virtual;

    // ========== INTERNAL FUNCTIONS ========== //

    function _getAmountWithSlippage(
        uint256 amount_,
        uint24 slippage_
    ) internal pure returns (uint256) {
        if (slippage_ > ONE_HUNDRED_PERCENT) {
            revert Callback_Params_PercentOutOfBounds(slippage_, 0, ONE_HUNDRED_PERCENT);
        }

        return (amount_ * (ONE_HUNDRED_PERCENT - slippage_)) / ONE_HUNDRED_PERCENT;
    }

    function _tokensRequiredForPool(
        uint256 amount_,
        uint24 proceedsUtilisationPercent_
    ) internal pure returns (uint256) {
        return (amount_ * proceedsUtilisationPercent_) / ONE_HUNDRED_PERCENT;
    }

    function _getLatestLinearVestingModule() internal view returns (address) {
        AuctionHouse auctionHouseContract = AuctionHouse(AUCTION_HOUSE);
        Keycode moduleKeycode = Keycode.wrap(LINEAR_VESTING_KEYCODE);

        // Get the module status
        (uint8 latestVersion, bool isSunset) = auctionHouseContract.getModuleStatus(moduleKeycode);

        if (isSunset || latestVersion == 0) {
            revert Callback_LinearVestingModuleNotFound();
        }

        return address(
            auctionHouseContract.getModuleForVeecode(wrapVeecode(moduleKeycode, latestVersion))
        );
    }

    function _getEncodedVestingParams(
        uint48 start_,
        uint48 expiry_
    ) internal pure returns (bytes memory) {
        return abi.encode(ILinearVesting.VestingParams({start: start_, expiry: expiry_}));
    }

    /// @notice Mint vesting tokens from an ERC20 token
    ///
    /// @param  token_          The ERC20 token to mint the vesting tokens from
    /// @param  quantity_       The quantity of tokens to mint
    /// @param  module_         The LinearVesting module to mint the tokens with
    /// @param  recipient_      The recipient of the vesting tokens
    /// @param  vestingStart_   The start of the vesting period
    /// @param  vestingExpiry_  The end of the vesting period
    function _mintVestingTokens(
        ERC20 token_,
        uint256 quantity_,
        LinearVesting module_,
        address recipient_,
        uint48 vestingStart_,
        uint48 vestingExpiry_
    ) internal {
        // Approve spending of the tokens
        token_.approve(address(module_), quantity_);

        // Mint the vesting tokens (it will deploy if necessary)
        module_.mint(
            recipient_,
            address(token_),
            _getEncodedVestingParams(vestingStart_, vestingExpiry_),
            quantity_,
            true // Wrap vesting LP tokens so they are easily visible
        );

        // The LinearVesting module will use all of `poolTokenQuantity`, so there is no need to clean up dangling approvals
    }
}
