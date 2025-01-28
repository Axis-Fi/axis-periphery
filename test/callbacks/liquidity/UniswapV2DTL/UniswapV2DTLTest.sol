// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "@forge-std-1.9.1/Test.sol";
import {Callbacks} from "@axis-core-1.0.1/lib/Callbacks.sol";
import {Permit2User} from "@axis-core-1.0.1-test/lib/permit2/Permit2User.sol";

import {IAuction} from "@axis-core-1.0.1/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "@axis-core-1.0.1/interfaces/IAuctionHouse.sol";
import {BatchAuctionHouse} from "@axis-core-1.0.1/BatchAuctionHouse.sol";

import {IUniswapV2Factory} from "@uniswap-v2-core-1.0.1/interfaces/IUniswapV2Factory.sol";
import {UniswapV2FactoryClone} from "../../../lib/uniswap-v2/UniswapV2FactoryClone.sol";

import {IUniswapV2Router02} from "@uniswap-v2-periphery-1.0.1/interfaces/IUniswapV2Router02.sol";
import {UniswapV2Router02} from "@uniswap-v2-periphery-1.0.1/UniswapV2Router02.sol";

import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";
import {UniswapV2DirectToLiquidity} from "../../../../src/callbacks/liquidity/UniswapV2DTL.sol";
import {LinearVesting} from "@axis-core-1.0.1/modules/derivatives/LinearVesting.sol";
import {MockBatchAuctionModule} from
    "@axis-core-1.0.1-test/modules/Auction/MockBatchAuctionModule.sol";

import {keycodeFromVeecode, toKeycode} from "@axis-core-1.0.1/modules/Keycode.sol";

import {MockERC20} from "@solmate-6.7.0/test/utils/mocks/MockERC20.sol";

import {WithSalts} from "../../../lib/WithSalts.sol";
import {TestConstants} from "../../../Constants.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";

abstract contract UniswapV2DirectToLiquidityTest is Test, Permit2User, WithSalts, TestConstants {
    using Callbacks for UniswapV2DirectToLiquidity;

    address internal constant _PROTOCOL = address(0x3);
    address internal constant _BUYER = address(0x4);
    address internal constant _NOT_SELLER = address(0x20);

    uint96 internal constant _LOT_CAPACITY = 10e18;
    uint24 internal constant _MAX_SLIPPAGE = 1; // 0.01%

    uint48 internal constant _START = 1_000_000;
    uint48 internal constant _DURATION = 1 days;
    uint48 internal constant _AUCTION_START = _START + 1;
    uint48 internal constant _AUCTION_CONCLUSION = _AUCTION_START + _DURATION;

    uint96 internal _lotId = 1;

    BatchAuctionHouse internal _auctionHouse;
    UniswapV2DirectToLiquidity internal _dtl;
    address internal _dtlAddress;
    IUniswapV2Factory internal _uniV2Factory;
    IUniswapV2Router02 internal _uniV2Router;
    LinearVesting internal _linearVesting;
    MockBatchAuctionModule internal _batchAuctionModule;

    MockERC20 internal _quoteToken;
    MockERC20 internal _baseToken;

    uint96 internal _lotCapacity = _LOT_CAPACITY;
    uint96 internal _proceeds;
    uint96 internal _refund;

    // TODO consider setting floor of max slippage to 0.01%

    // Inputs
    UniswapV2DirectToLiquidity.UniswapV2OnCreateParams internal _uniswapV2CreateParams =
        UniswapV2DirectToLiquidity.UniswapV2OnCreateParams({maxSlippage: uint24(_MAX_SLIPPAGE)});
    BaseDirectToLiquidity.OnCreateParams internal _dtlCreateParams = BaseDirectToLiquidity
        .OnCreateParams({
        poolPercent: 100e2,
        vestingStart: 0,
        vestingExpiry: 0,
        recipient: _SELLER,
        implParams: abi.encode(_uniswapV2CreateParams)
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

        // Create a UniswapV2Factory at a deterministic address
        UniswapV2FactoryClone uniV2Factory = new UniswapV2FactoryClone();
        _uniV2Factory = UniswapV2FactoryClone(_UNISWAP_V2_FACTORY);
        vm.etch(address(_uniV2Factory), address(uniV2Factory).code);
        // No storage slots to set

        // Create a UniswapV2Router at a deterministic address
        vm.startBroadcast();
        bytes32 uniswapV2RouterSalt = _getTestSalt(
            "UniswapV2Router",
            type(UniswapV2Router02).creationCode,
            abi.encode(address(_uniV2Factory), address(0))
        );
        _uniV2Router =
            new UniswapV2Router02{salt: uniswapV2RouterSalt}(address(_uniV2Factory), address(0));
        vm.stopBroadcast();
        if (address(_uniV2Router) != _UNISWAP_V2_ROUTER) {
            console2.log("UniswapV2Router address: {}", address(_uniV2Router));
            revert("UniswapV2Router address mismatch");
        }

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
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: true,
            onCurate: true,
            onPurchase: false,
            onBid: false,
            onSettle: true,
            receiveQuoteTokens: true,
            sendBaseTokens: false
        });

        // Get the salt
        bytes memory args = abi.encode(
            address(_auctionHouse), address(_uniV2Factory), address(_uniV2Router), permissions
        );
        bytes32 salt = _getTestSalt(
            "UniswapV2DirectToLiquidity", type(UniswapV2DirectToLiquidity).creationCode, args
        );

        // Required for CREATE2 address to work correctly. doesn't do anything in a test
        // Source: https://github.com/foundry-rs/foundry/issues/6402
        vm.startBroadcast();
        _dtl = new UniswapV2DirectToLiquidity{salt: salt}(
            address(_auctionHouse), address(_uniV2Factory), address(_uniV2Router), permissions
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

    function _setMaxSlippage(
        uint24 maxSlippage_
    ) internal {
        _uniswapV2CreateParams.maxSlippage = maxSlippage_;
        _dtlCreateParams.implParams = abi.encode(_uniswapV2CreateParams);
    }

    modifier givenMaxSlippage(
        uint24 maxSlippage_
    ) {
        _setMaxSlippage(maxSlippage_);
        _;
    }

    modifier givenQuoteTokenDecimals(
        uint8 decimals_
    ) {
        _quoteToken = new MockERC20("Quote Token", "QT", decimals_);
        _;
    }

    modifier givenBaseTokenDecimals(
        uint8 decimals_
    ) {
        _baseToken = new MockERC20("Base Token", "BT", decimals_);

        // Scale the capacity
        _lotCapacity = uint96(_LOT_CAPACITY * 10 ** decimals_ / 10 ** 18);
        _;
    }

    function _createLot(address seller_, bytes memory err_) internal returns (uint96 lotId) {
        // Mint and approve the capacity to the owner
        _baseToken.mint(seller_, _lotCapacity);
        vm.prank(seller_);
        _baseToken.approve(address(_auctionHouse), _lotCapacity);

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
            start: _AUCTION_START,
            duration: _DURATION,
            capacityInQuote: false,
            capacity: _lotCapacity,
            implParams: abi.encode("")
        });

        if (err_.length > 0) {
            vm.expectRevert(err_);
        }

        // Create a new lot
        vm.prank(seller_);
        return _auctionHouse.auction(routingParams, auctionParams, "");
    }

    function _createLot(
        address seller_
    ) internal returns (uint96 lotId) {
        return _createLot(seller_, "");
    }

    modifier givenOnCreate() {
        _lotId = _createLot(_SELLER);
        _;
    }

    function _performOnCreate(
        address seller_
    ) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCreate(
            _lotId,
            seller_,
            address(_baseToken),
            address(_quoteToken),
            _lotCapacity,
            false,
            abi.encode(_dtlCreateParams)
        );
    }

    function _performOnCreate() internal {
        _performOnCreate(_SELLER);
    }

    function _performOnCurate(
        uint96 curatorPayout_
    ) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCurate(_lotId, curatorPayout_, false, abi.encode(""));
    }

    modifier givenOnCurate(
        uint96 curatorPayout_
    ) {
        _performOnCurate(curatorPayout_);
        _;
    }

    function _performOnCancel(uint96 lotId_, uint256 refundAmount_) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCancel(lotId_, refundAmount_, false, abi.encode(""));
    }

    function _performOnCancel() internal {
        _performOnCancel(_lotId, 0);
    }

    function _performOnSettle(
        uint96 lotId_
    ) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onSettle(lotId_, _proceeds, _refund, abi.encode(""));
    }

    function _performOnSettle() internal {
        _performOnSettle(_lotId);
    }

    function _setPoolPercent(
        uint24 percent_
    ) internal {
        _dtlCreateParams.poolPercent = percent_;
    }

    modifier givenPoolPercent(
        uint24 percent_
    ) {
        _setPoolPercent(percent_);
        _;
    }

    modifier givenVestingStart(
        uint48 start_
    ) {
        _dtlCreateParams.vestingStart = start_;
        _;
    }

    modifier givenVestingExpiry(
        uint48 end_
    ) {
        _dtlCreateParams.vestingExpiry = end_;
        _;
    }

    modifier whenRecipientIsNotSeller() {
        _dtlCreateParams.recipient = _NOT_SELLER;
        _;
    }

    // ========== FUNCTIONS ========== //

    function _getDTLConfiguration(
        uint96 lotId_
    ) internal view returns (BaseDirectToLiquidity.DTLConfiguration memory) {
        (
            address recipient_,
            uint256 lotCapacity_,
            uint256 lotCuratorPayout_,
            uint24 poolPercent_,
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
            poolPercent: poolPercent_,
            vestingStart: vestingStart_,
            vestingExpiry: vestingExpiry_,
            linearVestingModule: linearVestingModule_,
            active: active_,
            implParams: implParams_
        });
    }
}
