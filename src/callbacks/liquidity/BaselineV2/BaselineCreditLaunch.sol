// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// Axis dependencies
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";
import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {Callbacks} from "@axis-core-1.0.0/lib/Callbacks.sol";
import {IAuctionHouse} from "@axis-core-1.0.0/interfaces/IAuctionHouse.sol";
import {
    Keycode as AxisKeycode,
    keycodeFromVeecode,
    fromKeycode as fromAxisKeycode
} from "@axis-core-1.0.0/modules/Keycode.sol";
import {Module as AxisModule} from "@axis-core-1.0.0/modules/Modules.sol";
import {IFixedPriceBatch} from "@axis-core-1.0.0/interfaces/modules/auctions/IFixedPriceBatch.sol";

// Baseline dependencies
import {
    Kernel,
    Policy,
    Keycode as BaselineKeycode,
    toKeycode as toBaselineKeycode,
    Permissions as BaselinePermissions
} from "./lib/Kernel.sol";
import {Range, IBPOOLv1} from "./lib/IBPOOL.sol";
import {CreditAccount, ICREDTv1} from "./lib/ICREDT.sol";
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";

// Other libraries
import {Owned} from "@solmate-6.7.0/auth/Owned.sol";
import {FixedPointMathLib} from "@solady-0.0.124/utils/FixedPointMathLib.sol";
// import {Transfer, ERC20} from "@axis-core-1.0.0/lib/Transfer.sol";
// import {SqrtPriceMath} from "../../../lib/uniswap-v3/SqrtPriceMath.sol";

/// @notice     Axis auction callback to sell credit positions in a Baseline token before it is launched
/// @dev        This contract combines Baseline's InitializeProtocol Policy and Axis' Callback functionality to build an Axis auction callback specific to Baseline V2 token launches
///             It is designed to be used with a single auction and Baseline pool
contract BaselineCreditLaunch is BaseCallback, Policy, Owned, ERC20 {
    using FixedPointMathLib for uint256;

    // ========== ERRORS ========== //

    /// @notice The address of the base token (passed in the `onCreate` callback) does not match the address of the bAsset that the callback was initialized with
    error Callback_Params_BAssetTokenMismatch(address baseToken_, address bAsset_);

    /// @notice The address of the quote token (passed in the `onCreate` callback) does not match the address of the reserve that the callback was initialized with
    error Callback_Params_ReserveTokenMismatch(address quoteToken_, address reserve_);

    /// @notice The auction format is not supported
    error Callback_Params_UnsupportedAuctionFormat();
    
    /// @notice The user has an insufficient balance to claim their credit position
    error Callback_InsufficientBalance();

    /// @notice The auction tied to this callbacks contract has already been completed
    error Callback_AlreadyComplete();

    /// @notice The required funds were not sent to this callbacks contract
    error Callback_MissingFunds();

    /// @notice The BPOOL reserve token does not match the configured `RESERVE` address
    error InvalidModule();

    // ========== EVENTS ========== //

    event LiquidityDeployed(int24 tickLower, int24 tickUpper, uint128 liquidity);

    // ========== DATA STRUCTURES ========== //

    /// @notice Data struct for the onCreate callback
    ///
    /// @param  recipient               Address to receive the proceeds from the credit sale
    /// @param  creditDuration          Duration to set the credit accounts for
    /// @param  allowlistParams         Additional parameters for an allowlist, passed to `__onCreate()` for further processing
    struct CreateData {
        address recipient;
        uint256 creditDuration;
        bytes allowlistParams;
    }

    // ========== STATE VARIABLES ========== //

    // Baseline Modules
    // solhint-disable-next-line var-name-mixedcase
    IBPOOLv1 public BPOOL;
    ICREDTv1 public CREDT;

    // Pool variables
    ERC20 public immutable RESERVE;
    ERC20 public bAsset;

    // Axis Auction Variables

    /// @notice Lot ID of the auction for the baseline market. This callback only supports one lot.
    /// @dev    This value is initialised with the uint96 max value to indicate that it has not been set yet.
    uint96 public lotId;

    /// @notice Indicates whether the auction is complete
    /// @dev    This is used to prevent the callback from being called multiple times. It is set in the `onSettle()` callback.
    bool public auctionComplete;

    /// @notice The address to receive the proceeds from the credit sale
    address public recipient;

    /// @notice The BLV price for the credit accounts
    uint256 public blv;

    /// @notice The duration to set the credit accounts for
    uint256 public creditDuration;

    /// @notice The expiry time for the credit accounts
    uint256 public expiry;

    // solhint-disable-next-line private-vars-leading-underscore
    uint48 internal constant ONE_HUNDRED_PERCENT = 100e2;

    // ========== CONSTRUCTOR ========== //

    /// @notice Constructor for BaselineAxisLaunch
    ///
    /// @param  auctionHouse_   The AuctionHouse the callback is paired with
    /// @param  baselineKernel_ Address of the Baseline kernel
    /// @param  reserve_        Address of the reserve token. This should match the quote token for the auction lot.
    /// @param  owner_          Address of the owner of this policy. Will be permitted to perform admin functions. This is explicitly required, as `msg.sender` cannot be used due to the use of CREATE2 for deployment.
    constructor(
        address auctionHouse_,
        address baselineKernel_,
        address reserve_,
        address owner_
    )
        BaseCallback(
            auctionHouse_,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: true,
                onCurate: true,
                onPurchase: false,
                onBid: true,
                onSettle: true,
                receiveQuoteTokens: true,
                sendBaseTokens: true
            })
        )
        Policy(Kernel(baselineKernel_))
        Owned(owner_)
        ERC20("Baseline Credit Position", "BCP", 18)
    {
        // Set lot ID to max uint(96) initially so it doesn't reference a lot
        lotId = type(uint96).max;

        // Set the reserve token
        RESERVE = ERC20(reserve_);
    }

    // ========== POLICY FUNCTIONS ========== //

    /// @inheritdoc Policy
    function configureDependencies()
        external
        override
        returns (BaselineKeycode[] memory dependencies)
    {
        BaselineKeycode bpool = toBaselineKeycode("BPOOL");
        BaselineKeycode credt = toBaselineKeycode("CREDT");

        // Populate the dependencies array
        dependencies = new BaselineKeycode[](2);
        dependencies[0] = bpool;
        dependencies[1] = credt;

        // Set local values
        BPOOL = IBPOOLv1(getModuleAddress(bpool));
        bAsset = ERC20(address(BPOOL));
        CREDT = ICREDTv1(getModuleAddress(credt));

        // Change token name to match the BPOOL
        name = string.concat(bAsset.name(), " Credit Position");
        symbol = string.concat(bAsset.symbol(), "CP");

        // Require that the BPOOL's reserve token be the same as the callback's reserve token
        if (address(BPOOL.reserve()) != address(RESERVE)) revert InvalidModule();
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (BaselinePermissions[] memory requests)
    {
        BaselineKeycode bpool = toBaselineKeycode("BPOOL");
        BaselineKeycode credt = toBaselineKeycode("CREDT");

        requests = new BaselinePermissions[](2);
        requests[0] = BaselinePermissions(bpool, BPOOL.mint.selector);
        requests[0] = BaselinePermissions(credt, CREDT.updateCreditAccount.selector);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    // CALLBACK PERMISSIONS
    // onCreate: true
    // onCancel: true
    // onCurate: true
    // onPurchase: false
    // onBid: true
    // onSettle: true
    // receiveQuoteTokens: true
    // sendBaseTokens: true
    // Contract prefix should be: 11101111 = 0xEF

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 - Performs validation
    ///                 - Sets the `lotId`, `percentReservesFloor`, `anchorTickWidth`, and `discoveryTickWidth` variables
    ///                 - Calls the allowlist callback
    ///                 - Mints the required bAsset tokens to the AuctionHouse
    ///
    ///                 This function reverts if:
    ///                 - `baseToken_` is not the same as `bAsset`
    ///                 - `quoteToken_` is not the same as `RESERVE`
    ///                 - `lotId` is already set
    ///                 - `CreateData.floorReservesPercent` is less than 0% or greater than 100%
    ///                 - `CreateData.anchorTickWidth` is 0
    ///                 - `CreateData.discoveryTickWidth` is 0
    ///                 - The auction format is not supported
    ///                 - The auction is not prefunded
    ///                 - The active tick of the Baseline pool (from `baseToken_`) is not the same as the tick corresponding to the auction price
    function _onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal override {
        // Validate the base token is this contract
        // and the quote token is the reserve
        if (baseToken_ != address(this)) {
            revert Callback_Params_BAssetTokenMismatch(baseToken_, address(this));
        }
        if (quoteToken_ != address(RESERVE)) {
            revert Callback_Params_ReserveTokenMismatch(quoteToken_, address(RESERVE));
        }

        // Validate that the lot ID is not already set
        if (lotId != type(uint96).max) revert Callback_InvalidParams();

        // Decode the provided callback data (must be correctly formatted even if not using parts of it)
        CreateData memory cbData = abi.decode(callbackData_, (CreateData));

        // Validate that the recipient is not the zero address
        if (cbData.recipient == address(0)) revert Callback_InvalidParams();

        // Validate credit duration is not zero
        if (cbData.creditDuration == 0) revert Callback_InvalidParams();

        // Auction must be prefunded for batch auctions (which is the only type supported with this callback),
        // this can't fail because it's checked in the AH as well, but including for completeness
        if (!prefund_) revert Callback_Params_UnsupportedAuctionFormat();

        // Set the lot ID
        lotId = lotId_;

        // Set the recipient of the proceeds
        recipient = cbData.recipient;

        // Set the BLV price for the credit accounts
        blv = BPOOL.getBaselineValue();

        // Set the credit duration
        creditDuration = cbData.creditDuration;

        // Get the auction format
        AxisKeycode auctionFormat = keycodeFromVeecode(
            AxisModule(address(IAuctionHouse(AUCTION_HOUSE).getAuctionModuleForId(lotId))).VEECODE()
        );

        // Only supports Fixed Price Batch Auctions initially
        // TODO could also support EMP auctions
        if (fromAxisKeycode(auctionFormat) != bytes5("FPBA")) {
            revert Callback_Params_UnsupportedAuctionFormat();
        }

        // This contract can be extended with an allowlist for the auction
        // Call a lower-level function where this information can be used
        // We do this before token interactions to conform to CEI
        __onCreate(
            lotId_, seller_, baseToken_, quoteToken_, capacity_, prefund_, cbData.allowlistParams
        );

        // Mint the capacity of local tokens to the auction house to prefund the auction
        _mint(msg.sender, capacity_);
    }

    /// @notice Override this function to implement allowlist functionality
    function __onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes memory allowlistData_
    ) internal virtual {}

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 - Performs validation
    ///                 - Burns the refunded bAsset tokens
    ///
    ///                 This function has the following assumptions:
    ///                 - BaseCallback has already validated the lot ID
    ///                 - The AuctionHouse has already sent the correct amount of bAsset tokens
    ///
    ///                 This function reverts if:
    ///                 - `lotId_` is not the same as the stored `lotId`
    ///                 - The auction is already complete
    ///                 - Sufficient quantity of `bAsset` have not been sent to the callback
    function _onCancel(uint96 lotId_, uint256 refund_, bool, bytes calldata) internal override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Validate that the lot is not already settled or cancelled
        if (auctionComplete) revert Callback_AlreadyComplete();

        // Burn any refunded tokens (all auctions are prefunded)
        // Verify that the callback received the correct amount of bAsset tokens
        if (balanceOf[address(this)] < refund_) revert Callback_MissingFunds();

        // Set the auction lot to be cancelled
        auctionComplete = true;

        // Burn the refunded tokens
        _burn(address(this), refund_);
    }

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 - Performs validation
    ///
    ///                 This function has the following assumptions:
    ///                 - BaseCallback has already validated the lot ID
    ///
    ///                 This function reverts if:
    ///                 - `lotId_` is not the same as the stored `lotId`
    ///                 - The curator fee is non-zero
    function _onCurate(
        uint96 lotId_,
        uint256 curatorFee_,
        bool,
        bytes calldata
    ) internal override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Mint the curator fee to the auction house
        _mint(msg.sender, curatorFee_);
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented since atomic auctions are not supported
    function _onPurchase(
        uint96,
        address,
        uint256,
        uint256,
        bool,
        bytes calldata
    ) internal pure override {
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    /// @dev        No logic is needed for this function here, but it can be overridden by a lower-level contract to provide allowlist functionality
    function _onBid(
        uint96 lotId_,
        uint64 bidId,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual override {}

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 - Performs validation
    ///                 - Sets the auction as complete
    ///                 - Burns any refunded bAsset tokens
    ///                 - Calculates the deployment parameters for the Baseline pool
    ///                 - EMP auction format: calculates the ticks based on the clearing price
    ///                 - Deploys reserves into the Baseline pool
    ///
    ///                 Note that there may be reserve assets left over after liquidity deployment, which must be manually withdrawn by the owner using `withdrawReserves()`.
    ///
    ///                 Next steps:
    ///                 - Activate the market making and credit facility policies in the Baseline stack, which cannot be enabled before the auction is settled and the pool is initialized
    ///
    ///                 This function has the following assumptions:
    ///                 - BaseCallback has already validated the lot ID
    ///                 - The AuctionHouse has already sent the correct amount of quote tokens (proceeds)
    ///                 - The AuctionHouse is pre-funded, so does not require additional base tokens (bAssets) to be supplied
    ///
    ///                 This function reverts if:
    ///                 - `lotId_` is not the same as the stored `lotId`
    ///                 - The auction is already complete
    ///                 - The reported proceeds received are less than the reserve balance
    ///                 - The reported refund received is less than the bAsset balance
    function _onSettle(
        uint96 lotId_,
        uint256 proceeds_,
        uint256 refund_,
        bytes calldata
    ) internal virtual override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Validate that the auction is not already complete
        if (auctionComplete) revert Callback_AlreadyComplete();

        // Validate that the callback received the correct amount of proceeds
        // As this is a single-use contract, reserve balance is likely 0 prior, but extra funds will not affect it
        if (proceeds_ > RESERVE.balanceOf(address(this))) revert Callback_MissingFunds();

        // Validate that the callback received the correct amount of base tokens as a refund
        // As this is a single-use contract and we control the minting of tokens, the balance should be 0
        if (refund_ > balanceOf[address(this)]) revert Callback_MissingFunds();

        // Set the auction as complete
        auctionComplete = true;

        //// Step 1: Burn any refunded tokens ////

        // Burn any refunded bAsset tokens that were sent from the auction house
        _burn(address(this), refund_);

        //// Step 2: Create credit position for this contract ////
        {
            uint256 collateral = totalSupply; // the size of the position is the supply of the token for this contract
            uint256 credit = collateral.mulWad(blv); // the credit is the BLV price of the position
            expiry = block.timestamp + creditDuration; // the credit expires after the credit duration

            // Mint the required bAssets to create the credit position
            BPOOL.mint(address(this), collateral);

            // Update the credit account
            CREDT.updateCreditAccount(address(this), collateral, credit, expiry);
        }

        //// Step 3: Send proceeds to recipient ////
        RESERVE.transfer(recipient, proceeds_);
    }
    
    // ========== CREDIT CLAIM ========== //

    /// @notice Allows a token holder to claim their credit position from this contract
    /// @dev    Transfers the position to the user and deletes their tokens so that the position
    ///         can be managed by the Baseline Credit Facility
    function claimCredit() external {
        // Check the user's balance and ensure it is atleast the collateral amount
        if (balanceOf[msg.sender] == 0) revert Callback_InsufficientBalance();

        // Burn the credit tokens from the user
        uint256 collateral = balanceOf[msg.sender];
        _burn(msg.sender, collateral);

        // Default outstanding debts in the system
        CREDT.defaultOutstanding();

        // Update this contract's credit account
        uint256 credit = collateral.mulWad(blv);

        CreditAccount memory account = CREDT.getCreditAccount(address(this));

        // This contract receives "collateral" bAssets on this call
        CREDT.updateCreditAccount(
            address(this),
            account.collateral - collateral,
            account.credit - credit,
            account.expiry
        );

        // Approve the credit account to transfer out the collateral
        bAsset.approve(address(CREDT), collateral);

        // Update the caller's credit account
        // This will transfer "collateral" bAssets to the CREDT module
        // Note: this allows them to extend their expiry if they have an existing position, otherwise it remains the same
        account = CREDT.getCreditAccount(msg.sender);
        uint256 newExpiry = account.expiry > expiry ? account.expiry : expiry;

        CREDT.updateCreditAccount(
            msg.sender,
            account.collateral + collateral,
            account.credit + credit,
            newExpiry
        );
    }


    // ========== OWNER FUNCTIONS ========== //

    /// @notice Withdraws any remaining reserve tokens from the contract
    /// @dev    This is access-controlled to the owner
    ///
    /// @return withdrawnAmount The amount of reserve tokens withdrawn
    function withdrawReserves() external onlyOwner returns (uint256 withdrawnAmount) {
        withdrawnAmount = RESERVE.balanceOf(address(this));

        RESERVE.transfer(owner, withdrawnAmount);

        return withdrawnAmount;
    }
}
