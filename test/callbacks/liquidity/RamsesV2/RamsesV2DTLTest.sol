// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Test scaffolding
import {Test} from "@forge-std-1.9.1/Test.sol";
import {Callbacks} from "@axis-core-1.0.0/lib/Callbacks.sol";
import {Permit2User} from "@axis-core-1.0.0-test/lib/permit2/Permit2User.sol";
import {WithSalts} from "../../../lib/WithSalts.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";
import {TestConstants} from "../../../Constants.sol";

// Mocks
import {MockERC20} from "@solmate-6.7.0/test/utils/mocks/MockERC20.sol";
import {MockBatchAuctionModule} from
    "@axis-core-1.0.0-test/modules/Auction/MockBatchAuctionModule.sol";

// Callbacks
import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";

// Ramses
import {RamsesV2DirectToLiquidity} from "../../../../src/callbacks/liquidity/Ramses/RamsesV2DTL.sol";
import {IRamsesV2Factory} from "../../../../src/callbacks/liquidity/Ramses/lib/IRamsesV2Factory.sol";
import {IRamsesV2Pool} from "../../../../src/callbacks/liquidity/Ramses/lib/IRamsesV2Pool.sol";
import {IRamsesV2PositionManager} from
    "../../../../src/callbacks/liquidity/Ramses/lib/IRamsesV2PositionManager.sol";

// Axis core
import {keycodeFromVeecode, toKeycode} from "@axis-core-1.0.0/modules/Keycode.sol";
import {IAuction} from "@axis-core-1.0.0/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "@axis-core-1.0.0/interfaces/IAuctionHouse.sol";
import {BatchAuctionHouse} from "@axis-core-1.0.0/BatchAuctionHouse.sol";
import {LinearVesting} from "@axis-core-1.0.0/modules/derivatives/LinearVesting.sol";

abstract contract RamsesV2DirectToLiquidityTest is Test, Permit2User, WithSalts, TestConstants {
    using Callbacks for RamsesV2DirectToLiquidity;

    address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);
    address internal constant _BUYER = address(0x4);
    address internal constant _NOT_SELLER = address(0x20);

    uint96 internal constant _LOT_CAPACITY = 10e18;

    uint48 internal _initialTimestamp;

    uint96 internal _lotId = 1;

    BatchAuctionHouse internal _auctionHouse;
    RamsesV2DirectToLiquidity internal _dtl;
    address internal _dtlAddress;
    IRamsesV2Factory internal _factory;
    IRamsesV2PositionManager internal _positionManager;
    MockBatchAuctionModule internal _batchAuctionModule;

    MockERC20 internal _quoteToken;
    MockERC20 internal _baseToken;

    // Inputs
    RamsesV2DirectToLiquidity.RamsesV2OnCreateParams internal _ramsesCreateParams = RamsesV2DirectToLiquidity
        .RamsesV2OnCreateParams({
        poolFee: 500,
        maxSlippage: 0,
        veRamTokenId: 0
    });
    BaseDirectToLiquidity.OnCreateParams internal _dtlCreateParams = BaseDirectToLiquidity
        .OnCreateParams({
        proceedsUtilisationPercent: 100e2,
        vestingStart: 0,
        vestingExpiry: 0,
        recipient: _SELLER,
        implParams: abi.encode(_ramsesCreateParams)
    });

    function setUp() public {
        // Create a fork on Arbitrum
        string memory arbitrumRpcUrl = vm.envString("ARBITRUM_RPC_URL");
        vm.createSelectFork(arbitrumRpcUrl);
        require(block.chainid == 42_161, "Must be on Arbitrum");

        _initialTimestamp = uint48(block.timestamp);

        // Create an AuctionHouse at a deterministic address, since it is used as input to callbacks
        BatchAuctionHouse auctionHouse = new BatchAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _auctionHouse = BatchAuctionHouse(_AUCTION_HOUSE);
        vm.etch(address(_auctionHouse), address(auctionHouse).code);
        vm.store(address(_auctionHouse), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner
        vm.store(address(_auctionHouse), bytes32(uint256(6)), bytes32(abi.encode(1))); // Reentrancy
        vm.store(address(_auctionHouse), bytes32(uint256(10)), bytes32(abi.encode(_PROTOCOL))); // Protocol

        _factory = IRamsesV2Factory(_RAMSES_V2_FACTORY);
        _positionManager = IRamsesV2PositionManager(payable(_RAMSES_V2_POSITION_MANAGER));

        _batchAuctionModule = new MockBatchAuctionModule(address(_auctionHouse));

        // Install a mock batch auction module
        vm.prank(_OWNER);
        _auctionHouse.installModule(_batchAuctionModule);

        _quoteToken = new MockERC20("Quote Token", "QT", 18);
        _baseToken = new MockERC20("Base Token", "BT", 18);
    }

    // ========== MODIFIERS ========== //

    modifier givenCallbackIsCreated() {
        // Get the salt
        bytes memory args =
            abi.encode(address(_auctionHouse), address(_factory), address(_positionManager));
        bytes32 salt = _getTestSalt(
            "RamsesV2DirectToLiquidity", type(RamsesV2DirectToLiquidity).creationCode, args
        );

        // Required for CREATE2 address to work correctly. doesn't do anything in a test
        // Source: https://github.com/foundry-rs/foundry/issues/6402
        vm.startBroadcast();
        _dtl = new RamsesV2DirectToLiquidity{salt: salt}(
            address(_auctionHouse), address(_factory), payable(_positionManager)
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

    function _performOnCurate(uint96 curatorPayout_) internal {
        vm.prank(address(_auctionHouse));
        _dtl.onCurate(_lotId, curatorPayout_, false, abi.encode(""));
    }

    modifier givenOnCurate(uint96 curatorPayout_) {
        _performOnCurate(curatorPayout_);
        _;
    }

    modifier givenProceedsUtilisationPercent(uint24 percent_) {
        _dtlCreateParams.proceedsUtilisationPercent = percent_;
        _;
    }

    modifier givenPoolFee(uint24 fee_) {
        _ramsesCreateParams.poolFee = fee_;

        // Update the callback data
        _dtlCreateParams.implParams = abi.encode(_ramsesCreateParams);
        _;
    }

    function _setMaxSlippage(uint24 maxSlippage_) internal {
        _ramsesCreateParams.maxSlippage = maxSlippage_;
        _dtlCreateParams.implParams = abi.encode(_ramsesCreateParams);
    }

    modifier givenMaxSlippage(uint24 maxSlippage_) {
        _setMaxSlippage(maxSlippage_);
        _;
    }

    function _setVmRamTokenId(uint24 vmRamTokenId_) internal {
        _ramsesCreateParams.veRamTokenId = vmRamTokenId_;
        _dtlCreateParams.implParams = abi.encode(_ramsesCreateParams);
    }

    modifier givenVmRamTokenId(uint24 vmRamTokenId_) {
        _setVmRamTokenId(vmRamTokenId_);
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
}
