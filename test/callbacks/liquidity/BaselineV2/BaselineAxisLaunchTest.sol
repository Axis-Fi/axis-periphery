// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Test scaffolding
import {Test} from "@forge-std-1.9.1/Test.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";
import {Permit2User} from "@axis-core-1.0.0-test/lib/permit2/Permit2User.sol";
import {WithSalts} from "../../../lib/WithSalts.sol";
import {MockERC20} from "@solmate-6.7.0/test/utils/mocks/MockERC20.sol";
import {IUniswapV3Factory} from
    "@uniswap-v3-core-1.0.1-solc-0.8-simulate/interfaces/IUniswapV3Factory.sol";
import {UniswapV3Factory} from "../../../lib/uniswap-v3/UniswapV3Factory.sol";
import {ComputeAddress} from "../../../lib/ComputeAddress.sol";
import {FixedPointMathLib} from "@solmate-6.7.0/utils/FixedPointMathLib.sol";
import {TestConstants} from "../../../Constants.sol";
import {SqrtPriceMath} from "../../../../src/lib/uniswap-v3/SqrtPriceMath.sol";
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";

// Axis core
import {IAuction} from "@axis-core-1.0.0/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "@axis-core-1.0.0/interfaces/IAuctionHouse.sol";
import {BatchAuctionHouse} from "@axis-core-1.0.0/BatchAuctionHouse.sol";
import {EncryptedMarginalPrice} from "@axis-core-1.0.0/modules/auctions/batch/EMP.sol";
import {IFixedPriceBatch} from "@axis-core-1.0.0/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "@axis-core-1.0.0/modules/auctions/batch/FPB.sol";

// Callbacks
import {Callbacks} from "@axis-core-1.0.0/lib/Callbacks.sol";
import {BaselineAxisLaunch} from
    "../../../../src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";

// Baseline
import {Kernel as BaselineKernel, Actions as BaselineKernelActions} from "@baseline/Kernel.sol";
import {BPOOLv1, Range, Position} from "@baseline/modules/BPOOL.v1.sol";
import {CREDTv1} from "@baseline/modules/CREDT.v1.sol";
import {BPOOLMinter} from "./BPOOLMinter.sol";
import {MarketMaking} from "@baseline/policies/MarketMaking.sol";

// solhint-disable max-states-count

abstract contract BaselineAxisLaunchTest is Test, Permit2User, WithSalts, TestConstants {
    using Callbacks for BaselineAxisLaunch;

    address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);
    address internal constant _BUYER = address(0x4);
    address internal constant _BORROWER = address(0x10);
    address internal constant _NOT_SELLER = address(0x20);

    uint24 internal constant _ONE_HUNDRED_PERCENT = 100e2;

    uint96 internal constant _LOT_CAPACITY = 10e18;
    uint96 internal constant _REFUND_AMOUNT = 2e18;
    uint256 internal constant _PROCEEDS_AMOUNT = 24e18;
    int24 internal constant _ANCHOR_TICK_WIDTH = 10;
    int24 internal constant _DISCOVERY_TICK_WIDTH = 350;
    uint24 internal constant _FLOOR_RESERVES_PERCENT = 50e2; // 50%
    uint24 internal constant _POOL_PERCENT = 87e2; // 87%
    uint256 internal constant _FIXED_PRICE = 3e18;
    int24 internal constant _FIXED_PRICE_TICK_UPPER = 11_000; // 10986 rounded up
    uint256 internal constant _INITIAL_POOL_PRICE = 3e18; // 3
    uint24 internal constant _FEE_TIER = 10_000;
    uint256 internal constant _BASE_SCALE = 1e18;
    uint8 internal _quoteTokenDecimals = 18;
    uint8 internal _baseTokenDecimals = 18;
    bool internal _isBaseTokenAddressLower = true;
    /// @dev Set in `givenBPoolFeeTier()`
    uint24 internal _feeTier = _FEE_TIER;
    /// @dev Set in `_setPoolInitialTickFromAuctionPrice()`
    int24 internal _poolInitialTick;
    /// @dev Set in `_setFloorRangeGap()`
    int24 internal _floorRangeGap;
    uint48 internal _protocolFeePercent;
    uint256 internal _protocolFee;
    uint48 internal _referrerFeePercent;
    uint256 internal _referrerFee;
    uint48 internal _curatorFeePercent;
    uint256 internal _curatorFee;

    uint256 internal _proceeds = _PROCEEDS_AMOUNT;
    uint256 internal _refund = _REFUND_AMOUNT;

    uint48 internal constant _START = 1_000_000;

    uint96 internal _lotId = 1;

    BatchAuctionHouse internal _auctionHouse;
    EncryptedMarginalPrice internal _empModule;
    FixedPriceBatch internal _fpbModule;
    BaselineAxisLaunch internal _dtl;
    address internal _dtlAddress;
    IUniswapV3Factory internal _uniV3Factory;

    int24 internal _tickSpacing;

    IAuction internal _auctionModule;

    MockERC20 internal _quoteToken;
    BaselineKernel internal _baselineKernel;
    BPOOLv1 internal _baseToken;
    CREDTv1 internal _creditModule;
    MarketMaking internal _marketMaking;
    BPOOLMinter internal _bPoolMinter;

    // Inputs
    IFixedPriceBatch.AuctionDataParams internal _fpbParams = IFixedPriceBatch.AuctionDataParams({
        price: _FIXED_PRICE,
        minFillPercent: 50e2 // 50%
    });

    BaselineAxisLaunch.CreateData internal _createData = BaselineAxisLaunch.CreateData({
        recipient: _SELLER,
        poolPercent: _POOL_PERCENT,
        floorReservesPercent: _FLOOR_RESERVES_PERCENT,
        floorRangeGap: _floorRangeGap,
        anchorTickU: _FIXED_PRICE_TICK_UPPER,
        anchorTickWidth: _ANCHOR_TICK_WIDTH,
        allowlistParams: abi.encode("")
    });

    function setUp() public {
        // Set reasonable timestamp
        vm.warp(_START);

        // Create an BatchAuctionHouse at a deterministic address, since it is used as input to callbacks
        BatchAuctionHouse auctionHouse = new BatchAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _auctionHouse = BatchAuctionHouse(_AUCTION_HOUSE);
        vm.etch(address(_auctionHouse), address(auctionHouse).code);
        vm.store(address(_auctionHouse), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner
        vm.store(address(_auctionHouse), bytes32(uint256(6)), bytes32(abi.encode(1))); // Reentrancy
        vm.store(address(_auctionHouse), bytes32(uint256(10)), bytes32(abi.encode(_PROTOCOL))); // Protocol

        // Create a UniswapV3Factory at a deterministic address
        vm.startBroadcast();
        bytes32 uniswapV3Salt =
            _getTestSalt("UniswapV3Factory", type(UniswapV3Factory).creationCode, abi.encode());
        _uniV3Factory = new UniswapV3Factory{salt: uniswapV3Salt}();
        vm.stopBroadcast();
        if (address(_uniV3Factory) != _UNISWAP_V3_FACTORY) {
            console2.log("UniswapV3Factory address: ", address(_uniV3Factory));
            revert("UniswapV3Factory address mismatch");
        }

        // Create the Baseline kernel at a deterministic address, since it is used as input to callbacks
        vm.prank(_OWNER);
        BaselineKernel baselineKernel = new BaselineKernel();
        _baselineKernel = BaselineKernel(_BASELINE_KERNEL);
        vm.etch(address(_baselineKernel), address(baselineKernel).code);
        vm.store(address(_baselineKernel), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner

        // Create auction modules
        _empModule = new EncryptedMarginalPrice(address(_auctionHouse));
        _fpbModule = new FixedPriceBatch(address(_auctionHouse));

        // Default auction module is FPB
        _auctionModule = _fpbModule;
        _mockGetAuctionModuleForId();

        // Create the quote token at a deterministic address
        bytes32 quoteTokenSalt = _getTestSalt(
            "QuoteToken", type(MockERC20).creationCode, abi.encode("Quote Token", "QT", 18)
        );
        vm.prank(_CREATE2_DEPLOYER);
        _quoteToken = new MockERC20{salt: quoteTokenSalt}("Quote Token", "QT", 18);
        _quoteTokenDecimals = 18;
        if (address(_quoteToken) != _BASELINE_QUOTE_TOKEN) {
            console2.log("Quote Token address: ", address(_quoteToken));
            revert("Quote Token address mismatch");
        }

        _tickSpacing = _uniV3Factory.feeAmountTickSpacing(_feeTier);
        console2.log("Tick spacing: ", _tickSpacing);

        // Set up Baseline
        _creditModule = new CREDTv1(_baselineKernel);
        _marketMaking = new MarketMaking(_baselineKernel, 25, 1000, 3e18, address(0));
        // Base token is created in the givenBPoolIsCreated modifier
        _bPoolMinter = new BPOOLMinter(_baselineKernel);

        // Calculate the initial tick
        _setPoolInitialTickFromPrice(_INITIAL_POOL_PRICE);
    }

    // ========== MODIFIERS ========== //

    function _setPoolInitialTickFromTick(int24 tick_) internal {
        _poolInitialTick = tick_;
        console2.log("Pool initial tick (using tick) set to: ", _poolInitialTick);
    }

    function _setPoolInitialTickFromPrice(uint256 price_) internal {
        _poolInitialTick = _getTickFromPrice(price_, _baseTokenDecimals, _isBaseTokenAddressLower);
        console2.log("Pool initial tick (using specified price) set to: ", _poolInitialTick);
    }

    function _setPoolInitialTickFromAuctionPrice() internal {
        console2.log("Auction price: ", _fpbParams.price);
        _poolInitialTick =
            _getTickFromPrice(_fpbParams.price, _baseTokenDecimals, _isBaseTokenAddressLower);
        console2.log("Pool initial tick (using auction price) set to: ", _poolInitialTick);
    }

    modifier givenPoolInitialTick(int24 poolInitialTick_) {
        _setPoolInitialTickFromTick(poolInitialTick_);
        _;
    }

    function _setFloorRangeGap(int24 tickSpacingWidth_) internal {
        _floorRangeGap = tickSpacingWidth_;
        console2.log("Floor range gap set to: ", _floorRangeGap);
        _createData.floorRangeGap = _floorRangeGap;
    }

    modifier givenFloorRangeGap(int24 tickSpacingWidth_) {
        _setFloorRangeGap(tickSpacingWidth_);
        _;
    }

    function _createBPOOL() internal {
        // Generate a salt so that the base token address is higher (or lower) than the quote token
        console2.log("Generating salt for BPOOL");
        bytes32 baseTokenSalt = ComputeAddress.generateSalt(
            _BASELINE_QUOTE_TOKEN,
            !_isBaseTokenAddressLower,
            type(BPOOLv1).creationCode,
            abi.encode(
                _baselineKernel,
                "Base Token",
                "BT",
                _baseTokenDecimals,
                address(_uniV3Factory),
                _BASELINE_QUOTE_TOKEN,
                _feeTier,
                _poolInitialTick
            ),
            address(this)
        );

        // Create a new BPOOL with the given fee tier
        console2.log("Creating BPOOL");
        _baseToken = new BPOOLv1{salt: baseTokenSalt}(
            _baselineKernel,
            "Base Token",
            "BT",
            _baseTokenDecimals,
            address(_uniV3Factory),
            _BASELINE_QUOTE_TOKEN,
            _feeTier,
            _poolInitialTick
        );

        // Assert that the token ordering is correct
        if (_isBaseTokenAddressLower) {
            require(address(_baseToken) < _BASELINE_QUOTE_TOKEN, "Base token > quote token");
        } else {
            require(address(_baseToken) > _BASELINE_QUOTE_TOKEN, "Base token < quote token");
        }

        // Install the BPOOL module
        vm.prank(_OWNER);
        _baselineKernel.executeAction(BaselineKernelActions.InstallModule, address(_baseToken));

        // Install the CREDT module
        vm.prank(_OWNER);
        _baselineKernel.executeAction(BaselineKernelActions.InstallModule, address(_creditModule));

        // Activate MarketMaking
        vm.prank(_OWNER);
        _baselineKernel.executeAction(BaselineKernelActions.ActivatePolicy, address(_marketMaking));

        // Activate the BPOOL minter
        vm.prank(_OWNER);
        _baselineKernel.executeAction(BaselineKernelActions.ActivatePolicy, address(_bPoolMinter));
    }

    modifier givenBPoolIsCreated() {
        _createBPOOL();
        _;
    }

    function _createCallback() internal {
        if (address(_baseToken) == address(0)) {
            revert("Base token not created");
        }

        // Get the salt
        bytes memory args =
            abi.encode(address(_auctionHouse), _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN);
        bytes32 salt =
            _getTestSalt("BaselineAxisLaunch", type(BaselineAxisLaunch).creationCode, args);

        // Required for CREATE2 address to work correctly. doesn't do anything in a test
        // Source: https://github.com/foundry-rs/foundry/issues/6402
        vm.startBroadcast();
        _dtl = new BaselineAxisLaunch{salt: salt}(
            address(_auctionHouse), _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN
        );
        vm.stopBroadcast();

        _dtlAddress = address(_dtl);

        // Install as a policy
        vm.prank(_OWNER);
        _baselineKernel.executeAction(BaselineKernelActions.ActivatePolicy, _dtlAddress);
    }

    modifier givenCallbackIsCreated() virtual {
        _createCallback();
        _;
    }

    modifier givenAuctionFormatIsEmp() {
        _auctionModule = _empModule;
        _mockGetAuctionModuleForId();
        _;
    }

    function _createAuction() internal {
        console2.log("");
        console2.log("Creating auction in FPB module");

        // Create a dummy auction in the module
        IAuction.AuctionParams memory auctionParams = IAuction.AuctionParams({
            start: _START,
            duration: 1 days,
            capacityInQuote: false,
            capacity: _scaleBaseTokenAmount(_LOT_CAPACITY),
            implParams: abi.encode(_fpbParams)
        });

        vm.prank(address(_auctionHouse));
        _fpbModule.auction(_lotId, auctionParams, _quoteTokenDecimals, _baseTokenDecimals);
    }

    modifier givenAuctionIsCreated() {
        _createAuction();
        _;
    }

    function _onCreate() internal {
        console2.log("");
        console2.log("Calling onCreate callback");
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            _SELLER,
            address(_baseToken),
            address(_quoteToken),
            _scaleBaseTokenAmount(_LOT_CAPACITY),
            true,
            abi.encode(_createData)
        );
    }

    modifier givenOnCreate() {
        _onCreate();
        _;
    }

    function _onCancel() internal {
        console2.log("");
        console2.log("Calling onCancel callback");
        vm.prank(address(_auctionHouse));
        _dtl.onCancel(_lotId, _scaleBaseTokenAmount(_LOT_CAPACITY), true, abi.encode(""));
    }

    modifier givenOnCancel() {
        _onCancel();
        _;
    }

    function _onSettle(bytes memory err_) internal {
        console2.log("");
        console2.log("Calling onSettle callback");

        uint256 capacityRefund = _scaleBaseTokenAmount(_refund);
        console2.log("capacity refund", capacityRefund);
        uint256 curatorFeeRefund = capacityRefund * _curatorFee / _LOT_CAPACITY;
        console2.log("curator fee refund", curatorFeeRefund);

        if (err_.length > 0) {
            vm.expectRevert(err_);
        }

        vm.prank(address(_auctionHouse));
        _dtl.onSettle(_lotId, _proceeds, capacityRefund + curatorFeeRefund, abi.encode(""));
    }

    function _onSettle() internal {
        _onSettle("");
    }

    modifier givenOnSettle() {
        _onSettle();
        _;
    }

    function _onCurate(uint256 curatorFee_) internal {
        console2.log("");
        console2.log("Calling onCurate callback");
        vm.prank(address(_auctionHouse));
        _dtl.onCurate(_lotId, curatorFee_, true, abi.encode(""));
    }

    modifier givenOnCurate(uint256 curatorFee_) {
        _onCurate(curatorFee_);
        _;
    }

    modifier givenBPoolFeeTier(uint24 feeTier_) {
        _feeTier = feeTier_;
        _tickSpacing = _uniV3Factory.feeAmountTickSpacing(_feeTier);
        _;
    }

    modifier givenBaseTokenAddressHigher() {
        _isBaseTokenAddressLower = false;

        _setPoolInitialTickFromAuctionPrice();
        _;
    }

    modifier givenBaseTokenDecimals(uint8 decimals_) {
        _baseTokenDecimals = decimals_;

        _setPoolInitialTickFromAuctionPrice();
        _;
    }

    modifier givenFixedPrice(uint256 fixedPrice_) {
        _fpbParams.price = fixedPrice_;
        console2.log("Fixed price set to: ", fixedPrice_);

        _setPoolInitialTickFromAuctionPrice();
        _;
    }

    modifier givenAnchorUpperTick(int24 anchorTickU_) {
        _createData.anchorTickU = anchorTickU_;
        console2.log("Anchor tick U set to: ", anchorTickU_);
        _;
    }

    function _setAnchorTickWidth(int24 anchorTickWidth_) internal {
        _createData.anchorTickWidth = anchorTickWidth_;
    }

    modifier givenAnchorTickWidth(int24 anchorTickWidth_) {
        _setAnchorTickWidth(anchorTickWidth_);
        _;
    }

    function _scaleBaseTokenAmount(uint256 amount_) internal view returns (uint256) {
        return FixedPointMathLib.mulDivDown(amount_, 10 ** _baseTokenDecimals, _BASE_SCALE);
    }

    modifier givenAddressHasBaseTokenBalance(address account_, uint256 amount_) {
        _mintBaseTokens(account_, amount_);
        _;
    }

    modifier givenAddressHasQuoteTokenBalance(address account_, uint256 amount_) {
        console2.log("Minting quote tokens to: ", account_);
        _quoteToken.mint(account_, amount_);
        _;
    }

    function _transferBaseTokenRefund(uint256 amount_) internal {
        console2.log("Transferring base token refund to DTL: ", amount_);
        // Transfer refund from auction house to the callback
        // We transfer instead of minting to not affect the supply
        vm.prank(address(_auctionHouse));
        _baseToken.transfer(_dtlAddress, amount_);
    }

    modifier givenBaseTokenRefundIsTransferred(uint256 amount_) {
        _transferBaseTokenRefund(amount_);
        _;
    }

    function _getTickFromPrice(
        uint256 price_,
        uint8 baseTokenDecimals_,
        bool isBaseTokenAddressLower_
    ) internal pure returns (int24 tick) {
        // Get sqrtPriceX96
        uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(
            _BASELINE_QUOTE_TOKEN,
            isBaseTokenAddressLower_
                ? address(0x0000000000000000000000000000000000000001)
                : address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF),
            price_,
            10 ** baseTokenDecimals_
        );

        // Convert to tick
        return TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    function _getRangeReserves(Range range_) internal view returns (uint256) {
        Position memory position = _baseToken.getPosition(range_);

        return position.reserves;
    }

    function _getRangeBAssets(Range range_) internal view returns (uint256) {
        Position memory position = _baseToken.getPosition(range_);

        return position.bAssets;
    }

    function _mintBaseTokens(address account_, uint256 amount_) internal {
        vm.prank(_OWNER);
        _bPoolMinter.mint(account_, amount_);
    }

    function _setPoolPercent(uint24 poolPercent_) internal {
        _createData.poolPercent = poolPercent_;
    }

    modifier givenPoolPercent(uint24 poolPercent_) {
        _setPoolPercent(poolPercent_);
        _;
    }

    function _setFloorReservesPercent(uint24 floorReservesPercent_) internal {
        _createData.floorReservesPercent = floorReservesPercent_;
    }

    modifier givenFloorReservesPercent(uint24 floorReservesPercent_) {
        _setFloorReservesPercent(floorReservesPercent_);
        _;
    }

    function _roundToTickSpacingUp(int24 activeTick_) internal view returns (int24) {
        // Rounds down
        int24 roundedTick = (activeTick_ / _tickSpacing) * _tickSpacing;

        // Add a tick spacing to round up
        // This mimics BPOOL.getActiveTS()
        if (activeTick_ >= 0 || activeTick_ % _tickSpacing == 0) {
            roundedTick += _tickSpacing;
        }

        return roundedTick;
    }

    function _mockLotFees() internal {
        // Mock on the AuctionHouse
        vm.mockCall(
            address(_auctionHouse),
            abi.encodeWithSelector(IAuctionHouse.lotFees.selector, _lotId),
            abi.encode(
                address(0), true, _curatorFeePercent, _protocolFeePercent, _referrerFeePercent
            )
        );
    }

    function _setCuratorFeePercent(uint48 curatorFeePercent_) internal {
        _curatorFeePercent = curatorFeePercent_;

        // Update mock
        _mockLotFees();

        // Update the value
        _curatorFee = _LOT_CAPACITY * _curatorFeePercent / 100e2;
    }

    modifier givenCuratorFeePercent(uint48 curatorFeePercent_) {
        _setCuratorFeePercent(curatorFeePercent_);
        _;
    }

    function _setProtocolFeePercent(uint48 protocolFeePercent_) internal {
        _protocolFeePercent = protocolFeePercent_;

        // Update mock
        _mockLotFees();

        // Update the value
        _protocolFee = _proceeds * _protocolFeePercent / 100e2;
    }

    modifier givenProtocolFeePercent(uint48 protocolFeePercent_) {
        _setProtocolFeePercent(protocolFeePercent_);
        _;
    }

    function _setReferrerFeePercent(uint48 referrerFeePercent_) internal {
        _referrerFeePercent = referrerFeePercent_;

        // Update mock
        _mockLotFees();

        // Update the value
        _referrerFee = _proceeds * _referrerFeePercent / 100e2;
    }

    modifier givenReferrerFeePercent(uint48 referrerFeePercent_) {
        _setReferrerFeePercent(referrerFeePercent_);
        _;
    }

    function _setTotalCollateralized(address user_, uint256 totalCollateralized_) internal {
        // Mint enough base tokens to cover the total collateralized
        _mintBaseTokens(user_, totalCollateralized_);

        // Approve the spending of the base tokens
        vm.prank(user_);
        _baseToken.approve(address(_bPoolMinter), totalCollateralized_);

        // Unlock transfers
        bool transfersLocked = _baseToken.locked();
        if (transfersLocked) {
            vm.prank(_OWNER);
            _bPoolMinter.setTransferLock(false);
        }

        // Borrow
        vm.prank(user_);
        _bPoolMinter.allocateCreditAccount(user_, totalCollateralized_, 365);

        // Re-lock transfers if locked previously
        if (transfersLocked) {
            vm.prank(_OWNER);
            _bPoolMinter.setTransferLock(true);
        }
    }

    modifier givenCollateralized(address user_, uint256 totalCollateralized_) {
        _setTotalCollateralized(user_, totalCollateralized_);
        _;
    }

    // ========== MOCKS ========== //

    function _mockGetAuctionModuleForId() internal {
        vm.mockCall(
            address(_auctionHouse),
            abi.encodeWithSelector(IAuctionHouse.getAuctionModuleForId.selector, _lotId),
            abi.encode(address(_auctionModule))
        );
    }
}
