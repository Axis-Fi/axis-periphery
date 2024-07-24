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

// Baseline dependencies
import {
    Kernel,
    Policy,
    Keycode as BaselineKeycode,
    toKeycode as toBaselineKeycode,
    Permissions as BaselinePermissions
} from "./lib/Kernel.sol";
import {Position, Range, IBPOOLv1} from "./lib/IBPOOL.sol";
import {ICREDTv1} from "./lib/ICREDT.sol";

// Other libraries
import {Owned} from "@solmate-6.7.0/auth/Owned.sol";
import {FixedPointMathLib} from "@solady-0.0.124/utils/FixedPointMathLib.sol";
import {Transfer} from "@axis-core-1.0.0/lib/Transfer.sol";

/// @notice     Axis auction callback to initialize a Baseline token using proceeds from a batch auction.
/// @dev        This contract combines Baseline's InitializeProtocol Policy and Axis' Callback functionality to build an Axis auction callback specific to Baseline V2 token launches
///             It is designed to be used with a single auction and Baseline pool
contract BaselineAxisLaunch is BaseCallback, Policy, Owned {
    using FixedPointMathLib for uint256;

    // ========== ERRORS ========== //

    /// @notice The address of the base token (passed in the `onCreate` callback) does not match the address of the bAsset that the callback was initialized with
    error Callback_Params_BAssetTokenMismatch(address baseToken_, address bAsset_);

    /// @notice The address of the quote token (passed in the `onCreate` callback) does not match the address of the reserve that the callback was initialized with
    error Callback_Params_ReserveTokenMismatch(address quoteToken_, address reserve_);

    /// @notice The auction price and the pool active tick do not match
    error Callback_Params_PoolTickMismatch(int24 auctionTick_, int24 poolTick_);

    /// @notice The auction format is not supported
    error Callback_Params_UnsupportedAuctionFormat();

    /// @notice The anchor tick width is invalid
    error Callback_Params_InvalidAnchorTickWidth();

    /// @notice The discovery tick width is invalid
    error Callback_Params_InvalidDiscoveryTickWidth();

    /// @notice The floor reserves percent is invalid
    error Callback_Params_InvalidFloorReservesPercent();

    /// @notice The pool percent is invalid
    error Callback_Params_InvalidPoolPercent();

    /// @notice The recipient address is invalid
    error Callback_Params_InvalidRecipient();

    /// @notice The auction tied to this callbacks contract has already been completed
    error Callback_AlreadyComplete();

    /// @notice The required funds were not sent to this callbacks contract
    error Callback_MissingFunds();

    /// @notice The initialization is invalid
    error Callback_InvalidInitialization();

    /// @notice The BPOOL reserve token does not match the configured `RESERVE` address
    error Callback_BPOOLReserveMismatch();

    /// @notice The address of the BPOOL is higher than the RESERVE token address, when it must be lower
    error Callback_BPOOLInvalidAddress();

    // ========== EVENTS ========== //

    event LiquidityDeployed(
        int24 floorTickLower, int24 anchorTickUpper, uint128 floorLiquidity, uint128 anchorLiquidity
    );

    // ========== DATA STRUCTURES ========== //

    /// @notice Data struct for the onCreate callback
    ///
    /// @param  recipient               The address to receive proceeds that do not go to the pool
    /// @param  poolPercent             The percentage of the proceeds to allocate to the pool, in basis points (1% = 100). The remainder will be sent to the `recipient`.
    /// @param  floorReservesPercent    The percentage of the pool proceeds to allocate to the floor range, in basis points (1% = 100). The remainder will be allocated to the anchor range.
    /// @param  anchorTickWidth         The width of the anchor tick range, as a multiple of the pool tick spacing.
    /// @param  discoveryTickWidth      The width of the discovery tick range, as a multiple of the pool tick spacing.
    /// @param  allowlistParams         Additional parameters for an allowlist, passed to `__onCreate()` for further processing
    struct CreateData {
        address recipient;
        uint24 poolPercent;
        uint24 floorReservesPercent;
        int24 anchorTickWidth;
        int24 discoveryTickWidth;
        bytes allowlistParams;
    }

    // ========== STATE VARIABLES ========== //

    // Baseline Modules
    // solhint-disable var-name-mixedcase
    IBPOOLv1 public BPOOL;
    ICREDTv1 public CREDT;

    // Pool variables
    ERC20 public immutable RESERVE;
    // solhint-enable var-name-mixedcase
    ERC20 public bAsset;

    // Axis Auction Variables

    /// @notice Lot ID of the auction for the baseline market. This callback only supports one lot.
    /// @dev    This value is initialised with the uint96 max value to indicate that it has not been set yet.
    uint96 public lotId;

    /// @notice Indicates whether the auction is complete
    /// @dev    This is used to prevent the callback from being called multiple times. It is set in the `onSettle()` callback.
    bool public auctionComplete;

    /// @notice The percentage of the proceeds to allocate to the pool
    /// @dev    This value is set in the `onCreate()` callback.
    uint24 public poolPercent;

    /// @notice The percentage of the proceeds to allocate to the floor range
    /// @dev    This value is set in the `onCreate()` callback.
    uint24 public floorReservesPercent;

    /// @notice The address to receive proceeds that do not go to the pool
    /// @dev    This value is set in the `onCreate()` callback.
    address public recipient;

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

        // Require that the BPOOL's reserve token be the same as the callback's reserve token
        if (address(BPOOL.reserve()) != address(RESERVE)) revert Callback_BPOOLReserveMismatch();
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (BaselinePermissions[] memory requests)
    {
        BaselineKeycode bpool = toBaselineKeycode("BPOOL");

        requests = new BaselinePermissions[](5);
        requests[0] = BaselinePermissions(bpool, BPOOL.addReservesTo.selector);
        requests[1] = BaselinePermissions(bpool, BPOOL.addLiquidityTo.selector);
        requests[2] = BaselinePermissions(bpool, BPOOL.burnAllBAssetsInContract.selector);
        requests[3] = BaselinePermissions(bpool, BPOOL.mint.selector);
        requests[4] = BaselinePermissions(bpool, BPOOL.setTicks.selector);
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
    ///                 - `baseToken_` is not lower than `quoteToken_`
    ///                 - `recipient` is the zero address
    ///                 - `lotId` is already set
    ///                 - `CreateData.floorReservesPercent` is greater than 99%
    ///                 - `CreateData.poolPercent` is less than 1% or greater than 100%
    ///                 - `CreateData.anchorTickWidth` is 0 or > 10
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
        // Validate the base token is the baseline token
        // and the quote token is the reserve
        if (baseToken_ != address(bAsset)) {
            revert Callback_Params_BAssetTokenMismatch(baseToken_, address(bAsset));
        }
        if (quoteToken_ != address(RESERVE)) {
            revert Callback_Params_ReserveTokenMismatch(quoteToken_, address(RESERVE));
        }
        // Ensure the base token is lower than the quote token
        if (address(bAsset) > address(RESERVE)) {
            revert Callback_BPOOLInvalidAddress();
        }

        // Validate that the lot ID is not already set
        if (lotId != type(uint96).max) revert Callback_InvalidParams();

        // Decode the provided callback data (must be correctly formatted even if not using parts of it)
        CreateData memory cbData = abi.decode(callbackData_, (CreateData));

        // Validate that the recipient is not the zero address
        if (cbData.recipient == address(0)) revert Callback_Params_InvalidRecipient();

        // Validate that the anchor tick width is at least 1 tick spacing and at most 10
        // Baseline supports only within this range
        if (cbData.anchorTickWidth <= 0 || cbData.anchorTickWidth > 10) {
            revert Callback_Params_InvalidAnchorTickWidth();
        }

        // Validate that the discovery tick width is at least 1 tick spacing
        if (cbData.discoveryTickWidth <= 0) {
            revert Callback_Params_InvalidDiscoveryTickWidth();
        }

        // Validate that the floor reserves percent is between 0% and 99%
        if (cbData.floorReservesPercent > 99e2) {
            revert Callback_Params_InvalidFloorReservesPercent();
        }

        // Validate that the pool percent is at least 1% and at most 100%
        if (cbData.poolPercent < 1e2 || cbData.poolPercent > 100e2) {
            revert Callback_Params_InvalidPoolPercent();
        }

        // Auction must be prefunded for batch auctions (which is the only type supported with this callback),
        // this can't fail because it's checked in the AH as well, but including for completeness
        if (!prefund_) revert Callback_Params_UnsupportedAuctionFormat();

        // Set the lot ID
        lotId = lotId_;

        // Set the recipient
        recipient = cbData.recipient;

        // Set the pool percent
        poolPercent = cbData.poolPercent;

        // Set the floor reserves percent
        floorReservesPercent = cbData.floorReservesPercent;

        // Get the auction format
        AxisKeycode auctionFormat = keycodeFromVeecode(
            AxisModule(address(IAuctionHouse(AUCTION_HOUSE).getAuctionModuleForId(lotId))).VEECODE()
        );

        // Only supports Fixed Price Batch Auctions initially
        if (fromAxisKeycode(auctionFormat) != bytes5("FPBA")) {
            revert Callback_Params_UnsupportedAuctionFormat();
        }

        // This contract can be extended with an allowlist for the auction
        // Call a lower-level function where this information can be used
        // We do this before token interactions to conform to CEI
        __onCreate(
            lotId_, seller_, baseToken_, quoteToken_, capacity_, prefund_, cbData.allowlistParams
        );

        // Set the ticks for the Baseline pool initially with the following assumptions:
        // - The floor range is 1 tick spacing wide
        // - The anchor range is `anchorTickWidth` tick spacings wide, above the floor range
        // - The discovery range is `discoveryTickWidth` tick spacings wide, above the anchor range
        // - The anchor range contains the active tick
        // - The anchor range upper tick is the active tick rounded up to the nearest tick spacing
        // - The other range boundaries are calculated accordingly
        {
            // Get the closest tick spacing boundary above the active tick
            // The active tick was set when the BPOOL was deployed
            // This is the top of the anchor range
            int24 anchorRangeUpper = BPOOL.getActiveTS();

            // Get the tick spacing from the pool
            int24 tickSpacing = BPOOL.TICK_SPACING();

            // Anchor range lower is the anchor tick width below the anchor range upper
            int24 anchorRangeLower = anchorRangeUpper - cbData.anchorTickWidth * tickSpacing;

            // Set the anchor range
            BPOOL.setTicks(Range.ANCHOR, anchorRangeLower, anchorRangeUpper);

            // Set the floor range
            // Floor range lower is the anchor range lower minus one tick spacing
            BPOOL.setTicks(Range.FLOOR, anchorRangeLower - tickSpacing, anchorRangeLower);

            // Set the discovery range
            BPOOL.setTicks(
                Range.DISCOVERY,
                anchorRangeUpper,
                anchorRangeUpper + tickSpacing * cbData.discoveryTickWidth
            );
        }

        // Mint the capacity of baseline tokens to the auction house to prefund the auction
        BPOOL.mint(msg.sender, capacity_);
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
        if (bAsset.balanceOf(address(this)) < refund_) revert Callback_MissingFunds();

        // Set the auction lot to be cancelled
        auctionComplete = true;

        // Send tokens to BPOOL and then burn
        Transfer.transfer(bAsset, address(BPOOL), refund_, false);
        BPOOL.burnAllBAssetsInContract();
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

        // Mint tokens for curator fee if it's not zero
        if (curatorFee_ > 0) {
            BPOOL.mint(msg.sender, curatorFee_);
        }
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
        // As this is a single-use contract and we control the minting of bAssets, bAsset balance is 0 prior
        if (refund_ > bAsset.balanceOf(address(this))) revert Callback_MissingFunds();

        // Set the auction as complete
        auctionComplete = true;

        //// Step 1: Burn any refunded bAsset tokens ////

        // Burn any refunded bAsset tokens that were sent from the auction house
        Transfer.transfer(bAsset, address(BPOOL), refund_, false);
        BPOOL.burnAllBAssetsInContract();

        //// Step 2: Deploy liquidity to the Baseline pool ////

        // Calculate the percent of proceeds to allocate to the pool
        uint256 poolProceeds = proceeds_ * poolPercent / ONE_HUNDRED_PERCENT;

        // Approve spending of the reserve token
        Transfer.approve(RESERVE, address(BPOOL), poolProceeds);

        // Add the configured percentage of the proceeds to the Floor range
        uint256 floorReserves = poolProceeds * floorReservesPercent / ONE_HUNDRED_PERCENT;
        BPOOL.addReservesTo(Range.FLOOR, floorReserves);

        // Add the remainder of the proceeds to the Anchor range
        BPOOL.addReservesTo(Range.ANCHOR, poolProceeds - floorReserves);

        // Ensure that there are no dangling approvals
        Transfer.approve(RESERVE, address(BPOOL), 0);

        // Add proportional liquidity to the Discovery range.
        // Only the anchor range is used, otherwise the liquidity would be too thick.
        // The anchor range is guranteed to have a tick spacing width
        // and to have reserves of at least 1% of the proceeds.
        BPOOL.addLiquidityTo(Range.DISCOVERY, BPOOL.getLiquidity(Range.ANCHOR) * 11 / 10);

        //// Step 4: Send remaining proceeds (and any excess reserves) to the recipient ////
        Transfer.transfer(RESERVE, recipient, RESERVE.balanceOf(address(this)), false);

        //// Step 5: Verify Solvency ////
        {
            uint256 totalSpotSupply = bAsset.totalSupply();
            uint256 totalCredit = CREDT.totalCreditIssued();
            uint256 totalCollatSupply = CREDT.totalCollateralized();

            Position memory floor = BPOOL.getPosition(Range.FLOOR);

            uint256 debtCapacity =
                BPOOL.getCapacityForReserves(floor.sqrtPriceL, floor.sqrtPriceU, totalCredit);

            uint256 totalCapacity = debtCapacity + BPOOL.getPosition(Range.FLOOR).capacity
                + BPOOL.getPosition(Range.ANCHOR).capacity + BPOOL.getPosition(Range.DISCOVERY).capacity;

            // verify the liquidity can support the intended supply
            // and that there is no significant initial surplus
            uint256 capacityRatio = totalCapacity.divWad(totalSpotSupply + totalCollatSupply);
            if (capacityRatio < 100e16 || capacityRatio > 102e16) {
                revert Callback_InvalidInitialization();
            }
        }

        // Emit an event
        {
            (int24 floorTickLower,) = BPOOL.getTicks(Range.FLOOR);
            (, int24 anchorTickUpper) = BPOOL.getTicks(Range.ANCHOR);
            emit LiquidityDeployed(
                floorTickLower,
                anchorTickUpper,
                BPOOL.getLiquidity(Range.FLOOR),
                BPOOL.getLiquidity(Range.ANCHOR)
            );
        }
    }

    // ========== OWNER FUNCTIONS ========== //

    /// @notice Withdraws any remaining reserve tokens from the contract
    /// @dev    This is access-controlled to the owner
    ///
    /// @return withdrawnAmount The amount of reserve tokens withdrawn
    function withdrawReserves() external onlyOwner returns (uint256 withdrawnAmount) {
        withdrawnAmount = RESERVE.balanceOf(address(this));

        Transfer.transfer(RESERVE, owner, withdrawnAmount, false);

        return withdrawnAmount;
    }
}
