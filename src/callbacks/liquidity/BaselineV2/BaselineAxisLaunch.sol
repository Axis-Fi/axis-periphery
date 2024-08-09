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
import {Transfer} from "@axis-core-1.0.0/lib/Transfer.sol";

// Baseline dependencies
import {
    Kernel,
    Policy,
    Keycode as BaselineKeycode,
    toKeycode as toBaselineKeycode,
    Permissions as BaselinePermissions
} from "./lib/Kernel.sol";
import {Position, Range, IBPOOLv1, IUniswapV3Pool} from "./lib/IBPOOL.sol";
import {ICREDTv1} from "./lib/ICREDT.sol";

// Other libraries
import {Owned} from "@solmate-6.7.0/auth/Owned.sol";
import {FixedPointMathLib} from "@solady-0.0.124/utils/FixedPointMathLib.sol";
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";
import {SqrtPriceMath} from "../../../lib/uniswap-v3/SqrtPriceMath.sol";

import {console2} from "@forge-std-1.9.1/console2.sol";

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

    /// @notice The auction format is not supported
    error Callback_Params_UnsupportedAuctionFormat();

    /// @notice The pool fee tier is not supported
    error Callback_Params_UnsupportedPoolFeeTier();

    /// @notice The anchor tick width is invalid
    error Callback_Params_InvalidAnchorTickWidth();

    /// @notice The discovery tick width is invalid
    error Callback_Params_InvalidDiscoveryTickWidth();

    /// @notice The floor range gap is invalid
    error Callback_Params_InvalidFloorRangeGap();

    /// @notice The anchor tick upper is invalid
    error Callback_Params_InvalidAnchorTickUpper();

    /// @notice One of the ranges is out of bounds
    error Callback_Params_RangeOutOfBounds();

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

    /// @notice The pool price is lower than the auction price
    error Callback_PoolLessThanAuctionPrice();

    /// @notice The BPOOL reserve token does not match the configured `RESERVE` address
    error Callback_BPOOLReserveMismatch();

    /// @notice The address of the BPOOL is higher than the RESERVE token address, when it must be lower
    error Callback_BPOOLInvalidAddress();

    /// @notice The caller to the Uniswap V3 swap callback is invalid
    error Callback_Swap_InvalidCaller();

    /// @notice The case for the Uniswap V3 swap callback is invalid
    error Callback_Swap_InvalidCase();

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
    /// @param  floorRangeGap           The gap between the floor and anchor ranges, as a multiple of the pool tick spacing.
    /// @param  anchorTickU             The upper tick of the anchor range. Validated against the calculated upper bound of the anchor range. This is provided off-chain to prevent front-running.
    /// @param  anchorTickWidth         The width of the anchor tick range, as a multiple of the pool tick spacing.
    /// @param  allowlistParams         Additional parameters for an allowlist, passed to `__onCreate()` for further processing
    struct CreateData {
        address recipient;
        uint24 poolPercent;
        uint24 floorReservesPercent;
        int24 floorRangeGap;
        int24 anchorTickU;
        int24 anchorTickWidth;
        bytes allowlistParams;
    }

    // ========== STATE VARIABLES ========== //

    // Baseline Modules
    // solhint-disable var-name-mixedcase
    IBPOOLv1 public BPOOL;
    ICREDTv1 public CREDT;

    // TickMath constants
    int24 internal constant _MAX_TICK = 887_272;
    int24 internal constant _MIN_TICK = -887_272;

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

    /// @notice The tick spacing width of the discovery range
    int24 internal constant _DISCOVERY_TICK_SPACING_WIDTH = 350;

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

        requests = new BaselinePermissions[](6);
        requests[0] = BaselinePermissions(bpool, BPOOL.addReservesTo.selector);
        requests[1] = BaselinePermissions(bpool, BPOOL.addLiquidityTo.selector);
        requests[2] = BaselinePermissions(bpool, BPOOL.burnAllBAssetsInContract.selector);
        requests[3] = BaselinePermissions(bpool, BPOOL.mint.selector);
        requests[4] = BaselinePermissions(bpool, BPOOL.setTicks.selector);
        requests[5] = BaselinePermissions(bpool, BPOOL.setTransferLock.selector);
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
    ///                 - The pool fee tier is not supported
    ///                 - `CreateData.floorReservesPercent` is greater than 99%
    ///                 - `CreateData.poolPercent` is less than 10% or greater than 100%
    ///                 - `CreateData.floorRangeGap` is < 0
    ///                 - `CreateData.anchorTickWidth` is < 10 or > 50
    ///                 - The auction format is not supported
    ///                 - The auction is not prefunded
    ///                 - Any of the tick ranges would exceed the tick bounds
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

        // Validate that the pool fee tier is supported
        // This callback only supports the 1% fee tier (tick spacing = 200)
        // as other fee tiers are not supported by the Baseline pool
        if (BPOOL.TICK_SPACING() != 200) revert Callback_Params_UnsupportedPoolFeeTier();

        // Validate that the floor range gap is at least 0
        if (cbData.floorRangeGap < 0) revert Callback_Params_InvalidFloorRangeGap();

        // Validate that the anchor tick width is at least 10 tick spacing and at most 50
        // Baseline supports only within this range
        if (cbData.anchorTickWidth < 10 || cbData.anchorTickWidth > 50) {
            revert Callback_Params_InvalidAnchorTickWidth();
        }

        // Validate that the floor reserves percent is between 0% and 99%
        if (cbData.floorReservesPercent > 99e2) {
            revert Callback_Params_InvalidFloorReservesPercent();
        }

        // Validate that the pool percent is at least 10% and at most 100%
        if (cbData.poolPercent < 10e2 || cbData.poolPercent > 100e2) {
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
            AxisModule(address(IAuctionHouse(AUCTION_HOUSE).getAuctionModuleForId(lotId_))).VEECODE(
            )
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
            // Check that the anchor tick range upper bound is the same
            // as the closest tick spacing boundary above the active tick on the BPOOL
            // We check this value against a parameter instead of reading
            // directly to avoid a situation where someone front-runs the
            // auction creation transaction and moves the active tick
            if (cbData.anchorTickU != BPOOL.getActiveTS()) {
                revert Callback_Params_InvalidAnchorTickUpper();
            }
            int24 anchorRangeUpper = cbData.anchorTickU;

            // Get the tick spacing from the pool
            int24 tickSpacing = BPOOL.TICK_SPACING();

            // Anchor range lower is the anchor tick width below the anchor range upper
            int24 anchorRangeLower = anchorRangeUpper - cbData.anchorTickWidth * tickSpacing;

            // Set the anchor range
            BPOOL.setTicks(Range.ANCHOR, anchorRangeLower, anchorRangeUpper);

            // Set the floor range
            // The creator can provide the `floorRangeGap` to space the floor range from the anchor range
            // If `floorRangeGap` is 0, the floor range will be directly below the anchor range
            // The floor range is one tick spacing wide
            int24 floorRangeUpper = anchorRangeLower - cbData.floorRangeGap * tickSpacing;
            int24 floorRangeLower = floorRangeUpper - tickSpacing;

            BPOOL.setTicks(Range.FLOOR, floorRangeLower, floorRangeUpper);

            // Set the discovery range
            int24 discoveryRangeUpper =
                anchorRangeUpper + tickSpacing * _DISCOVERY_TICK_SPACING_WIDTH;
            BPOOL.setTicks(Range.DISCOVERY, anchorRangeUpper, discoveryRangeUpper);

            // If the floor range lower tick (or any other above it) is below the min tick, it will cause problems
            // If the discovery range upper tick (or any other below it) is above the max tick, it will cause problems
            if (floorRangeLower < _MIN_TICK || discoveryRangeUpper > _MAX_TICK) {
                revert Callback_Params_RangeOutOfBounds();
            }
        }

        // Perform a pre-check to make sure the setup can be valid
        // This avoids certain bad configurations that would lead to failed initializations
        // Specifically, we check that the pool can support the intended supply
        // factoring in the capacity, curator fee, and any additional spot or collateralized supply
        // that already exists.
        // We assume that the auction capacity will be completely filled. This can be guaranteed by
        // setting the minFillPercent to 100e2 on the auction.
        {
            // Calculate the initial circulating supply
            uint256 initialCircSupply;
            {
                // Get the current supply values
                uint256 totalSupply = bAsset.totalSupply(); // can use totalSupply here since no bAssets are in the pool yet
                console2.log("totalSupply", totalSupply);
                uint256 currentCollatSupply = CREDT.totalCollateralized();
                console2.log("currentCollatSupply", currentCollatSupply);

                // Calculate the maximum curator fee that can be paid
                (,, uint48 curatorFeePerc,,) = IAuctionHouse(AUCTION_HOUSE).lotFees(lotId_);
                uint256 curatorFee = (capacity_ * curatorFeePerc) / ONE_HUNDRED_PERCENT;

                // Capacity and curator fee have not yet been minted, so we add those
                initialCircSupply = totalSupply + currentCollatSupply + capacity_ + curatorFee;
                console2.log("initialCircSupply", initialCircSupply);
            }

            // Calculate the initial capacity of the pool based on the ticks set and the expected proceeds to deposit in the pool
            uint256 initialCapacity;
            {
                IFixedPriceBatch auctionModule = IFixedPriceBatch(
                    address(IAuctionHouse(AUCTION_HOUSE).getAuctionModuleForId(lotId_))
                );

                // Get the fixed price from the auction module
                // This value is in the number of reserve tokens per baseline token
                uint256 auctionPrice = auctionModule.getAuctionData(lotId_).price;

                // Get the active tick from the pool and confirm it is >= the auction price corresponds to
                {
                    // We do this to avoid a situation where buyers are disincentivized to bid on the auction
                    // Pool price is number of token1 (reserve) per token0 (bAsset), which is what we want, but it needs to be squared
                    (, int24 activeTick,,,,,) = BPOOL.pool().slot0();

                    // Calculate the tick for the auction price
                    // `getSqrtPriceX96` handles token ordering
                    // The resulting tick will incorporate any differences in decimals between the tokens
                    uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(
                        address(RESERVE), address(bAsset), auctionPrice, 10 ** bAsset.decimals()
                    );
                    int24 auctionTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

                    // Verify that the active tick is at least the auction tick
                    if (activeTick < auctionTick) {
                        revert Callback_PoolLessThanAuctionPrice();
                    }
                }

                // Calculate the expected proceeds from the auction and how much will be deposited in the pool
                uint256 expectedProceeds = (auctionPrice * capacity_) / (10 ** bAsset.decimals());
                uint256 poolProceeds = (expectedProceeds * poolPercent) / ONE_HUNDRED_PERCENT;

                // Calculate the expected reserves for the floor and anchor ranges
                uint256 floorReserves = (poolProceeds * floorReservesPercent) / ONE_HUNDRED_PERCENT;
                uint256 anchorReserves = poolProceeds - floorReserves;

                // Calculate the expected capacity of the pool
                // Skip discovery range since no reserves will be deposited in it
                Position memory floor = BPOOL.getPosition(Range.FLOOR);
                Position memory anchor = BPOOL.getPosition(Range.ANCHOR);

                uint256 floorCapacity =
                    BPOOL.getCapacityForReserves(floor.sqrtPriceL, floor.sqrtPriceU, floorReserves);
                uint256 anchorCapacity = BPOOL.getCapacityForReserves(
                    anchor.sqrtPriceL, anchor.sqrtPriceU, anchorReserves
                );
                console2.log("floorCapacity", floorCapacity);
                console2.log("anchorCapacity", anchorCapacity);

                // Calculate the debt capacity at the floor range
                uint256 currentCredit = CREDT.totalCreditIssued();
                uint256 debtCapacity =
                    BPOOL.getCapacityForReserves(floor.sqrtPriceL, floor.sqrtPriceU, currentCredit);
                console2.log("debtCapacity", debtCapacity);

                // Calculate the total initial capacity of the pool
                initialCapacity = debtCapacity + floorCapacity + anchorCapacity;
                console2.log("initialCapacity", initialCapacity);
            }

            // Verify the liquidity can support the intended supply
            // and that there is no significant initial surplus
            //
            // If the solvency check is failing, it can be resolved by adjusting the following:
            // - auction price (via the auction fixed price)
            // - system liquidity (via the pool allocation and floor reserves allocation)
            uint256 capacityRatio = initialCapacity.divWad(initialCircSupply);
            console2.log("capacityRatio", capacityRatio);
            if (capacityRatio < 100e16 || capacityRatio > 102e16) {
                revert Callback_InvalidInitialization();
            }
        }

        // Allow BPOOL transfers if not already allowed
        // Transfers must be allowed so that the auction can be cancelled
        // and so that any refunded amount can be sent to this callback
        // when the auction is settled.
        // Because of this, it's important that no other spot tokens
        // are distributed prior to the auction being settled.
        if (BPOOL.locked()) BPOOL.setTransferLock(false);

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

        // Allow BPOOL transfers, if currently disabled
        if (BPOOL.locked()) BPOOL.setTransferLock(false);

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
            // Allow transfers if currently disabled
            // See comment in _onCreate for more information
            if (BPOOL.locked()) BPOOL.setTransferLock(false);

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
        // If there is a refund, then transfers would already need to be enabled
        // We check here anyway and enable transfers for the case where there is
        // no refund and it wouldn't have failed on that check.
        if (BPOOL.locked()) BPOOL.setTransferLock(false);

        // Burn any refunded bAsset tokens that were sent from the auction house
        Transfer.transfer(bAsset, address(BPOOL), refund_, false);
        BPOOL.burnAllBAssetsInContract();

        //// Step 2: Ensure the pool is at the correct price ////
        // Since there is no bAsset liquidity deployed yet,
        // External LPs can move the current price of the pool.
        // We move it back to the target active tick to ensure
        // the pool is at the correct price.
        {
            IUniswapV3Pool pool = BPOOL.pool();

            // TODO should we use rounded ticks instead of sqrtPrices?
            // Will minor inaccuracies cause issues with the check?
            // Current price of the pool
            (uint160 currentSqrtPrice,,,,,,) = pool.slot0();

            // Get the target sqrt price from the anchor position
            uint160 targetSqrtPrice = BPOOL.getPosition(Range.ANCHOR).sqrtPriceU;

            // We assume there are no circulating bAssets that could be provided as liquidity yet.
            // Therefore, there are three cases:
            // 1. The current price is above the target price
            if (currentSqrtPrice > targetSqrtPrice) {
                // In this case, an external LP has provided reserve liquidity above our range.
                // We can sell bAssets into this liquidity and the external LP will effectively be
                // bAssets at a premium to the initial price of the pool.
                // This does not affect the solvency of the system since the reserves received
                // are greater than the tokens minted, but it may cause the system to be
                // initialized with a surplus, which would allow for an immediate bump or snipe.
                //
                // We want to swap out all of the reserves currently in the pool above the target price for bAssets.
                // We just use the total balance in the pool because the price limit will prevent buying lower.
                int256 amount1Out = -int256(RESERVE.balanceOf(address(pool)));
                pool.swap(
                    address(this), // recipient
                    true, // zeroToOne, swapping token0 (bAsset) for token1 (reserve) so this is true
                    amount1Out, // amountSpecified, positive is exactIn, negative is exactOut
                    targetSqrtPrice, // sqrtPriceLimitX96
                    abi.encode(1) // data, case 1
                );
            }
            // 2. The current price is below the target price
            else if (currentSqrtPrice < targetSqrtPrice) {
                // Swap 1 wei of token1 (reserve) for token0 (bAsset) with a limit at the targetSqrtPrice
                // There are no bAssets in the pool, so we receive none. Because of this,
                // we don't end up paying any reserves either, but the price of the pool is shifted.
                pool.swap(
                    address(this), // recipient
                    false, // zeroToOne, swapping token1 (reserve) for token0 (bAsset) so this is false
                    int256(1), // amountSpecified, positive is exactIn, negative is exactOut
                    targetSqrtPrice, // sqrtPriceLimitX96
                    abi.encode(2) // data, case 2
                );
            }
            // 3. The current price is at the target price.
            //    If so, we don't need to do anything.

            // We don't need to track any of these amounts because the liquidity deployment and
            // will handle any extra reserves and the solvency check ensures that the system
            // can support the supply.

            // Check that the price is now at the target price
            (currentSqrtPrice,,,,,,) = pool.slot0();
            if (currentSqrtPrice != targetSqrtPrice) {
                revert Callback_InvalidInitialization();
            }
        }

        //// Step 3: Deploy liquidity to the Baseline pool ////

        // Calculate reserves to add to the pool
        // Because we potentially extracted reserves from the pool in the previous step,
        // we use the current balance minus the seller proceeds from the auction as
        // the pool proceeds amount so that the surplus is provided to the pool.
        // If no reserves were extracted, this will be the same amount as expected.
        uint256 sellerProceeds =
            proceeds_ * (ONE_HUNDRED_PERCENT - poolPercent) / ONE_HUNDRED_PERCENT;

        uint256 poolProceeds = RESERVE.balanceOf(address(this)) - sellerProceeds;

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
        //
        // TODO Reference: L-02 and L-07
        // Consider making the amount of discovery liquidity an onCreate parameter
        // This allows for more control over the liquidity distribution.
        // Specifically, it can enable configurations with high amounts of reserves
        // in the floor to still have adequate liquidity in the discovery range.
        // We need to check that the discovery liquidity is > the anchor liquidity that ends
        // up being deployed.
        BPOOL.addLiquidityTo(Range.DISCOVERY, BPOOL.getLiquidity(Range.ANCHOR) * 11 / 10);

        //// Step 4: Send remaining proceeds (and any excess reserves) to the recipient ////
        Transfer.transfer(RESERVE, recipient, RESERVE.balanceOf(address(this)), false);

        //// Step 5: Verify Solvency ////
        {
            uint256 totalSupply = bAsset.totalSupply();
            uint256 totalCollatSupply = CREDT.totalCollateralized();

            Position memory floor = BPOOL.getPosition(Range.FLOOR);
            Position memory anchor = BPOOL.getPosition(Range.ANCHOR);
            Position memory discovery = BPOOL.getPosition(Range.DISCOVERY);

            // Calculate the debt capacity at the floor range
            uint256 currentCredit = CREDT.totalCreditIssued();
            uint256 debtCapacity =
                BPOOL.getCapacityForReserves(floor.sqrtPriceL, floor.sqrtPriceU, currentCredit);

            uint256 totalCapacity =
                debtCapacity + floor.capacity + anchor.capacity + discovery.capacity;
            console2.log("totalCapacity", totalCapacity);
            console2.log("totalSupply", totalSupply);
            console2.log("totalCollatSupply", totalCollatSupply);
            uint256 totalSpotSupply =
                totalSupply - floor.bAssets - anchor.bAssets - discovery.bAssets;
            console2.log("totalSpotSupply", totalSpotSupply);

            // verify the liquidity can support the intended supply
            // we do not check for a surplus at this point to avoid a DoS attack vector
            // during the onCreate callback, we check for a surplus and there shouldn't
            // be one from this initialization at this point.
            // any surplus reserves added to the pool by a 3rd party before
            // the system is initialized will be snipable and effectively donated to the snipers
            uint256 capacityRatio = totalCapacity.divWad(totalSpotSupply + totalCollatSupply);
            console2.log("capacityRatio", capacityRatio);
            if (capacityRatio < 100e16) {
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

    // ========== UNIV3 FUNCTIONS ========== //

    // Provide tokens when adjusting the pool price via a swap before deploying liquidity
    function uniswapV3SwapCallback(int256 bAssetDelta_, int256, bytes calldata data_) external {
        // Only the pool can call
        address pool = address(BPOOL.pool());
        if (msg.sender != pool) revert Callback_Swap_InvalidCaller();

        // Decode the data
        (uint8 case_) = abi.decode(data_, (uint8));

        // Handle the swap case
        if (case_ == 1) {
            // Mint the bAsset delta to the pool (if greater than 0)
            // TODO should we cap the amount here? if we do we will need to revert and that will make it so the auction cannot be settled
            if (bAssetDelta_ > 0) {
                BPOOL.mint(pool, uint256(bAssetDelta_));
            }
        } else if (case_ == 2) {
            // Case 2: Swapped in 1 wei of reserve tokens
            // We don't need to do anything here
        } else {
            revert Callback_Swap_InvalidCase();
        }
    }
}
