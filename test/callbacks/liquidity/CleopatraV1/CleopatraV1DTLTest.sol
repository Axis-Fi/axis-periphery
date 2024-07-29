// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Test scaffolding
import {Test} from "@forge-std-1.9.1/Test.sol";
import {Callbacks} from "@axis-core-1.0.0/lib/Callbacks.sol";
import {Permit2User} from "@axis-core-1.0.0-test/lib/permit2/Permit2User.sol";
import {WithSalts} from "../../../lib/WithSalts.sol";
import {TestConstants} from "../../../Constants.sol";

// Mocks
import {MockERC20} from "@solmate-6.7.0/test/utils/mocks/MockERC20.sol";
import {MockBatchAuctionModule} from
    "@axis-core-1.0.0-test/modules/Auction/MockBatchAuctionModule.sol";

// Callbacks
import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";

// Cleopatra
import {CleopatraV1DirectToLiquidity} from "../../../../src/callbacks/liquidity/Cleopatra/CleopatraV1DTL.sol";
import {ICleopatraV1Factory} from "../../../../src/callbacks/liquidity/Cleopatra/lib/ICleopatraV1Factory.sol";
import {ICleopatraV1Router} from "../../../../src/callbacks/liquidity/Cleopatra/lib/ICleopatraV1Router.sol";

// Axis core
import {keycodeFromVeecode, toKeycode} from "@axis-core-1.0.0/modules/Keycode.sol";
import {IAuction} from "@axis-core-1.0.0/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "@axis-core-1.0.0/interfaces/IAuctionHouse.sol";
import {BatchAuctionHouse} from "@axis-core-1.0.0/BatchAuctionHouse.sol";
import {LinearVesting} from "@axis-core-1.0.0/modules/derivatives/LinearVesting.sol";

abstract contract CleopatraV1DirectToLiquidityTest is Test, Permit2User, WithSalts, TestConstants {
    using Callbacks for CleopatraV1DirectToLiquidity;

    address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);
    address internal constant _BUYER = address(0x4);
    address internal constant _NOT_SELLER = address(0x20);

    uint96 internal constant _LOT_CAPACITY = 10e18;

    uint48 internal _initialTimestamp;

    uint96 internal _lotId = 1;

    BatchAuctionHouse internal _auctionHouse;
    CleopatraV1DirectToLiquidity internal _dtl;
    address internal _dtlAddress;

    ICleopatraV1Factory internal _factory;
    ICleopatraV1Router internal _router;
    LinearVesting internal _linearVesting;
    MockBatchAuctionModule internal _batchAuctionModule;

    MockERC20 internal _quoteToken;
    MockERC20 internal _baseToken;

    uint96 internal _proceeds;
    uint96 internal _refund;

    // Inputs
    CleopatraV1DirectToLiquidity.CleopatraV1OnCreateParams internal _cleopatraCreateParams =
        CleopatraV1DirectToLiquidity.CleopatraV1OnCreateParams({stable: false, maxSlippage: uint24(0)});
    BaseDirectToLiquidity.OnCreateParams internal _dtlCreateParams = BaseDirectToLiquidity
        .OnCreateParams({
        proceedsUtilisationPercent: 100e2,
        vestingStart: 0,
        vestingExpiry: 0,
        recipient: _SELLER,
        implParams: abi.encode(_cleopatraCreateParams)
    });

    function setUp() public {
        // Create a fork on Arbitrum
        string memory arbitrumRpcUrl = vm.envString("ARBITRUM_RPC_URL");
        vm.createSelectFork(arbitrumRpcUrl);
        require(block.chainid == 42_161, "Must be on Arbitrum");

        _initialTimestamp = uint48(block.timestamp);

        // Create an BatchAuctionHouse at a deterministic address, since it is used as input to callbacks
        BatchAuctionHouse auctionHouse = new BatchAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _auctionHouse = BatchAuctionHouse(_AUCTION_HOUSE);
        vm.etch(address(_auctionHouse), address(auctionHouse).code);
        vm.store(address(_auctionHouse), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner
        vm.store(address(_auctionHouse), bytes32(uint256(6)), bytes32(abi.encode(1))); // Reentrancy
        vm.store(address(_auctionHouse), bytes32(uint256(10)), bytes32(abi.encode(_PROTOCOL))); // Protocol

        _factory = ICleopatraV1Factory(_CLEOPATRA_V1_FACTORY);
        _router = ICleopatraV1Router(payable(_CLEOPATRA_V1_ROUTER));

        _linearVesting = new LinearVesting(address(_auctionHouse));
        _batchAuctionModule = new MockBatchAuctionModule(address(_auctionHouse));

        // Install a mock batch auction module
        vm.prank(_OWNER);
        _auctionHouse.installModule(_batchAuctionModule);

        _quoteToken = new MockERC20("Quote Token", "QT", 18);
        _baseToken = new MockERC20("Base Token", "BT", 18);
    }

    // ========== MODIFIERS ========== //

    modifier givenLinearVestingModuleIsInstalled() {
        vm.prank(_OWNER);
        _auctionHouse.installModule(_linearVesting);
        _;
    }

    modifier givenCallbackIsCreated() {
        // Get the salt
        bytes memory args = abi.encode(address(_auctionHouse), address(_factory), address(_router));
        bytes32 salt = _getTestSalt(
            "CleopatraV1DirectToLiquidity", type(CleopatraV1DirectToLiquidity).creationCode, args
        );

        // Required for CREATE2 address to work correctly. doesn't do anything in a test
        // Source: https://github.com/foundry-rs/foundry/issues/6402
        vm.startBroadcast();
        _dtl = new CleopatraV1DirectToLiquidity{salt: salt}(
            address(_auctionHouse), address(_factory), payable(_router)
        );
        vm.stopBroadcast();

        _dtlAddress = address(_dtl);
        _;
    }

    modifier givenAddressHasQuoteTokenBalance(address address_, uint256 amount_) {
        _quoteToken.mint(address_, amount_);
        _;
    }

    modifier givenAddressHasBaseTokenBalance(address address_, uint256 amount_) {
        _baseToken.mint(address_, amount_);
        _;
    }

    modifier givenAddressHasQuoteTokenAllowance(address owner_, address spender_, uint256 amount_) {
        vm.prank(owner_);
        _quoteToken.approve(spender_, amount_);
        _;
    }

    modifier givenAddressHasBaseTokenAllowance(address owner_, address spender_, uint256 amount_) {
        vm.prank(owner_);
        _baseToken.approve(spender_, amount_);
        _;
    }

    function _createLot(address seller_) internal returns (uint96 lotId) {
        // Mint and approve the capacity to the owner
        _baseToken.mint(seller_, _LOT_CAPACITY);
        vm.prank(seller_);
        _baseToken.approve(address(_auctionHouse), _LOT_CAPACITY);

        // Prep the lot arguments
        IAuctionHouse.RoutingParams memory routingParams = IAuctionHouse.RoutingParams({
            auctionType: keycodeFromVeecode(_batchAuctionModule.VEECODE()),
            baseToken: address(_baseToken),
            quoteToken: address(_quoteToken),
            referrerFee: 0, // No referrer fee
            curator: address(0),
            callbacks: _dtl,
            callbackData: abi.encode(_dtlCreateParams),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode(""),
            wrapDerivative: false
        });

        IAuction.AuctionParams memory auctionParams = IAuction.AuctionParams({
            start: uint48(block.timestamp) + 1,
            duration: 1 days,
            capacityInQuote: false,
            capacity: _LOT_CAPACITY,
            implParams: abi.encode("")
        });

        // Create a new lot
        vm.prank(seller_);
        return _auctionHouse.auction(routingParams, auctionParams, "");
    }

    modifier givenOnCreate() {
        _lotId = _createLot(_SELLER);
        _;
    }

    function _performOnCreate(address seller_) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            seller_,
            address(_baseToken),
            address(_quoteToken),
            _LOT_CAPACITY,
            false,
            abi.encode(_dtlCreateParams)
        );
    }

    function _performOnCreate() internal {
        _performOnCreate(_SELLER);
    }

    function _performOnCancel(uint96 lotId_, uint256 refundAmount_) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCancel(lotId_, refundAmount_, false, abi.encode(""));
    }

    function _performOnCancel() internal {
        _performOnCancel(_lotId, 0);
    }

    function _performOnCurate(uint96 curatorPayout_) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCurate(_lotId, curatorPayout_, false, abi.encode(""));
    }

    modifier givenOnCurate(uint96 curatorPayout_) {
        _performOnCurate(curatorPayout_);
        _;
    }

    function _performOnSettle(uint96 lotId_) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onSettle(lotId_, _proceeds, _refund, abi.encode(""));
    }

    function _performOnSettle() internal {
        _performOnSettle(_lotId);
    }

    modifier givenProceedsUtilisationPercent(uint24 percent_) {
        _dtlCreateParams.proceedsUtilisationPercent = percent_;
        _;
    }

    modifier givenVestingStart(uint48 start_) {
        _dtlCreateParams.vestingStart = start_;
        _;
    }

    modifier givenVestingExpiry(uint48 end_) {
        _dtlCreateParams.vestingExpiry = end_;
        _;
    }

    modifier whenRecipientIsNotSeller() {
        _dtlCreateParams.recipient = _NOT_SELLER;
        _;
    }

    modifier givenStable(bool stable_) {
        _cleopatraCreateParams.stable = stable_;

        // Update the callback data
        _dtlCreateParams.implParams = abi.encode(_cleopatraCreateParams);
        _;
    }

    function _setMaxSlippage(uint24 maxSlippage_) internal {
        _cleopatraCreateParams.maxSlippage = maxSlippage_;
        _dtlCreateParams.implParams = abi.encode(_cleopatraCreateParams);
    }

    modifier givenMaxSlippage(uint24 maxSlippage_) {
        _setMaxSlippage(maxSlippage_);
        _;
    }

    // ========== FUNCTIONS ========== //

    function _getDTLConfiguration(uint96 lotId_)
        internal
        view
        returns (BaseDirectToLiquidity.DTLConfiguration memory)
    {
        (
            address recipient_,
            uint256 lotCapacity_,
            uint256 lotCuratorPayout_,
            uint24 proceedsUtilisationPercent_,
            uint48 vestingStart_,
            uint48 vestingExpiry_,
            LinearVesting linearVestingModule_,
            bool active_,
            bytes memory implParams_
        ) = _dtl.lotConfiguration(lotId_);

        return BaseDirectToLiquidity.DTLConfiguration({
            recipient: recipient_,
            lotCapacity: lotCapacity_,
            lotCuratorPayout: lotCuratorPayout_,
            proceedsUtilisationPercent: proceedsUtilisationPercent_,
            vestingStart: vestingStart_,
            vestingExpiry: vestingExpiry_,
            linearVestingModule: linearVestingModule_,
            active: active_,
            implParams: implParams_
        });
    }

    // ========== ASSERTIONS ========== //

    function _assertApprovals() internal view {
        // Router
        assertEq(
            _quoteToken.allowance(address(_dtl), address(_router)),
            0,
            "allowance: quote token: router"
        );
        assertEq(
            _baseToken.allowance(address(_dtl), address(_router)),
            0,
            "allowance: base token: router"
        );

        // LinearVesting
        assertEq(
            _quoteToken.allowance(address(_dtl), address(_linearVesting)),
            0,
            "allowance: quote token: linear vesting"
        );
        assertEq(
            _baseToken.allowance(address(_dtl), address(_linearVesting)),
            0,
            "allowance: base token: linear vesting"
        );
    }
}
