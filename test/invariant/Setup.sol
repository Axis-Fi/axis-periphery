// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "@forge-std-1.9.1/Test.sol";
import {Callbacks} from "@axis-core-1.0.4/lib/Callbacks.sol";
import {Permit2User} from "@axis-core-1.0.4-test/lib/permit2/Permit2User.sol";

import {IAuction} from "@axis-core-1.0.4/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "@axis-core-1.0.4/interfaces/IAuctionHouse.sol";
import {BatchAuctionHouse} from "@axis-core-1.0.4/BatchAuctionHouse.sol";
import {EncryptedMarginalPrice} from "@axis-core-1.0.4/modules/auctions/batch/EMP.sol";
import {IFixedPriceBatch} from "@axis-core-1.0.4/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {FixedPriceBatch} from "@axis-core-1.0.4/modules/auctions/batch/FPB.sol";

import {IUniswapV2Factory} from "@uniswap-v2-core-1.0.1/interfaces/IUniswapV2Factory.sol";
import {UniswapV2FactoryClone} from "../lib/uniswap-v2/UniswapV2FactoryClone.sol";

import {IUniswapV2Router02} from "@uniswap-v2-periphery-1.0.1/interfaces/IUniswapV2Router02.sol";
import {UniswapV2Router02} from "@uniswap-v2-periphery-1.0.1/UniswapV2Router02.sol";

import {GUniFactory} from "@g-uni-v1-core-0.9.9/GUniFactory.sol";
import {GUniPool} from "@g-uni-v1-core-0.9.9/GUniPool.sol";
import {IUniswapV3Factory} from
    "@uniswap-v3-core-1.0.1-solc-0.8-simulate/interfaces/IUniswapV3Factory.sol";

import {UniswapV3Factory} from "../lib/uniswap-v3/UniswapV3Factory.sol";
import {WETH9} from "./modules/WETH.sol";
import {SwapRouter} from "./modules/uniswapv3-periphery/SwapRouter.sol";
import {FixedPointMathLib} from "@solmate-6.8.0/utils/FixedPointMathLib.sol";
import {SqrtPriceMath} from "../../src/lib/uniswap-v3/SqrtPriceMath.sol";
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";

import {BaseDirectToLiquidity} from "../../src/callbacks/liquidity/BaseDTL.sol";
import {UniswapV2DirectToLiquidity} from "../../src/callbacks/liquidity/UniswapV2DTL.sol";
import {UniswapV3DirectToLiquidity} from "../../src/callbacks/liquidity/UniswapV3DTL.sol";
import {LinearVesting} from "@axis-core-1.0.4/modules/derivatives/LinearVesting.sol";
import {MockBatchAuctionModule} from
    "@axis-core-1.0.4-test/modules/Auction/MockBatchAuctionModule.sol";

import {keycodeFromVeecode, toKeycode} from "@axis-core-1.0.4/modules/Keycode.sol";

import {BaselineAxisLaunch} from "../../src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";

// Baseline
import {Kernel, Actions, Module, toKeycode as toBaselineKeycode} from "@baseline/Kernel.sol";

import {MockERC20} from "@solmate-6.8.0/test/utils/mocks/MockERC20.sol";
import {BPOOLv1, Range, Position} from "@baseline/modules/BPOOL.v1.sol";
import {BPOOLMinter} from "./modules/BPOOLMinter.sol";
import {CREDTMinter} from "./modules/CREDTMinter.sol";
import {CREDTv1} from "@baseline/modules/CREDT.v1.sol";
import {LOOPSv1} from "@baseline/modules/LOOPS.v1.sol";
import {ModuleTester, ModuleTestFixture} from "./modules/ModuleTester.sol";

import {WithSalts} from "../lib/WithSalts.sol";
import {TestConstants} from "../Constants.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";

import {MockBatchAuctionHouse} from "./mocks/MockBatchAuctionHouse.sol";
import {MockBlast} from "./mocks/MockBlast.sol";

abstract contract Setup is Test, Permit2User, WithSalts, TestConstants {
    using Callbacks for UniswapV2DirectToLiquidity;
    using Callbacks for UniswapV3DirectToLiquidity;
    using Callbacks for BaselineAxisLaunch;

    /*//////////////////////////////////////////////////////////////////////////
                                GLOBAL VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    uint96[] internal lotIdsV2;
    uint96[] internal lotIdsV3;

    address internal user0 = vm.addr(uint256(keccak256("User0")));
    address internal user1 = vm.addr(uint256(keccak256("User1")));
    address internal user2 = vm.addr(uint256(keccak256("User2")));
    address internal user3 = vm.addr(uint256(keccak256("User3")));
    address internal user4 = vm.addr(uint256(keccak256("User4")));
    address internal user5 = vm.addr(uint256(keccak256("User5")));
    address[] internal users = [user0, user1, user2, user3, user4, user5];

    // address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);

    uint96 internal constant _LOT_CAPACITY = 10e18;
    uint96 internal constant _REFUND_AMOUNT = 2e18;
    uint96 internal constant _PAYOUT_AMOUNT = 1e18;
    uint256 internal constant _PROCEEDS_AMOUNT = 24e18;
    uint256 internal constant _FIXED_PRICE = 3e18;
    uint24 internal constant _FEE_TIER = 10_000;
    uint256 internal constant _BASE_SCALE = 1e18;

    uint8 internal _quoteTokenDecimals = 18;
    uint8 internal _baseTokenDecimals = 18;

    bool internal _isBaseTokenAddressLower = true;

    uint24 internal _feeTier = _FEE_TIER;
    int24 internal _poolInitialTick;
    int24 internal _tickSpacing;

    uint48 internal constant _START = 1_000_000;

    uint96 internal _lotId = 1;

    string internal constant UNISWAP_PREFIX = "E6";
    string internal constant BASELINE_PREFIX = "EF";

    address internal _dtlV2Address;
    address internal _dtlV3Address;
    address internal _dtlBaselineAddress;

    IFixedPriceBatch.AuctionDataParams internal _fpbParams =
        IFixedPriceBatch.AuctionDataParams({price: _FIXED_PRICE, minFillPercent: 100e2});

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    BatchAuctionHouse internal _auctionHouse;
    MockBatchAuctionHouse internal _baselineAuctionHouse;

    UniswapV2DirectToLiquidity internal _dtlV2;

    IUniswapV2Factory internal _uniV2Factory;
    IUniswapV2Router02 internal _uniV2Router;

    UniswapV3DirectToLiquidity internal _dtlV3;

    IUniswapV3Factory internal _uniV3Factory;
    GUniFactory internal _gUniFactory;
    WETH9 internal _weth;
    SwapRouter internal _v3SwapRouter;

    BaselineAxisLaunch internal _dtlBaseline;

    EncryptedMarginalPrice internal _empModule;
    FixedPriceBatch internal _fpbModule;
    Kernel internal _kernel;

    LinearVesting internal _linearVesting;
    MockBatchAuctionModule internal _batchAuctionModule;
    IAuction internal _auctionModule;

    MockBlast internal _blast;

    MockERC20 internal _quoteToken;
    MockERC20 internal _baseToken;
    BPOOLv1 internal _baselineToken;
    CREDTv1 internal _credt;
    LOOPSv1 internal _loops;

    BPOOLMinter internal _bpoolMinter;
    CREDTMinter internal _credtMinter;

    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event MessageAddress(string a, address b);
    event MessageBytes(string a, bytes b);
    event MessageBytes32(string a, bytes32 b);
    event MessageString(string a, string b);
    event MessageNum(string a, uint256 b);

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setup() internal {
        // Set reasonable timestamp
        vm.warp(_START);

        // Create an BatchAuctionHouse at a deterministic address, since it is used as input to callbacks
        _auctionHouse = new BatchAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _baselineAuctionHouse = new MockBatchAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);

        _uniV2Factory = new UniswapV2FactoryClone();

        _uniV2Router = new UniswapV2Router02(address(_uniV2Factory), address(0));

        _linearVesting = new LinearVesting(address(_auctionHouse));
        _batchAuctionModule = new MockBatchAuctionModule(address(_auctionHouse));
        _empModule = new EncryptedMarginalPrice(address(_baselineAuctionHouse));
        _fpbModule = new FixedPriceBatch(address(_baselineAuctionHouse));

        _auctionModule = _fpbModule;

        // Install a mock batch auction module
        vm.prank(_OWNER);
        _auctionHouse.installModule(_batchAuctionModule);
        vm.prank(_OWNER);
        _auctionHouse.installModule(_linearVesting);

        _quoteToken = new MockERC20("Quote Token", "QT", 18);
        _baseToken = new MockERC20("Base Token", "BT", 18);

        bytes memory constructorArgs = abi.encodePacked(
            type(UniswapV2DirectToLiquidity).creationCode,
            abi.encode(address(_auctionHouse), address(_uniV2Factory), address(_uniV2Router))
        );

        string[] memory uniswapV2Inputs = new string[](7);
        uniswapV2Inputs[0] = "./test/invariant/helpers/salt_hash.sh";
        uniswapV2Inputs[1] = "--bytecodeHash";
        uniswapV2Inputs[2] = toHexString(keccak256(constructorArgs));
        uniswapV2Inputs[3] = "--prefix";
        uniswapV2Inputs[4] = UNISWAP_PREFIX;
        uniswapV2Inputs[5] = "--deployer";
        uniswapV2Inputs[6] = toString(address(this));

        bytes memory uniswapV2Res = vm.ffi(uniswapV2Inputs);
        bytes32 uniswapV2Salt = abi.decode(uniswapV2Res, (bytes32));

        _dtlV2 = new UniswapV2DirectToLiquidity{salt: uniswapV2Salt}(
            address(_auctionHouse), address(_uniV2Factory), address(_uniV2Router)
        );

        _dtlV2Address = address(_dtlV2);

        _uniV3Factory = new UniswapV3Factory();

        _weth = new WETH9();

        _v3SwapRouter = new SwapRouter(address(_uniV3Factory), address(_weth));

        _gUniFactory = new GUniFactory(address(_uniV3Factory));

        address payable gelatoAddress = payable(address(0x10));
        GUniPool poolImplementation = new GUniPool(gelatoAddress);
        _gUniFactory.initialize(address(poolImplementation), address(0), address(this));

        bytes memory v3SaltArgs = abi.encodePacked(
            type(UniswapV3DirectToLiquidity).creationCode,
            abi.encode(address(_auctionHouse), address(_uniV3Factory), address(_gUniFactory))
        );

        string[] memory uniswapV3Inputs = new string[](7);
        uniswapV3Inputs[0] = "./test/invariant/helpers/salt_hash.sh";
        uniswapV3Inputs[1] = "--bytecodeHash";
        uniswapV3Inputs[2] = toHexString(keccak256(v3SaltArgs));
        uniswapV3Inputs[3] = "--prefix";
        uniswapV3Inputs[4] = UNISWAP_PREFIX;
        uniswapV3Inputs[5] = "--deployer";
        uniswapV3Inputs[6] = toString(address(this));

        bytes memory uniswapV3Res = vm.ffi(uniswapV3Inputs);
        bytes32 uniswapV3Salt = abi.decode(uniswapV3Res, (bytes32));

        _dtlV3 = new UniswapV3DirectToLiquidity{salt: uniswapV3Salt}(
            address(_auctionHouse), address(_uniV3Factory), address(_gUniFactory)
        );

        _dtlV3Address = address(_dtlV3);

        _tickSpacing = _uniV3Factory.feeAmountTickSpacing(_feeTier);

        _blast = new MockBlast();

        _updatePoolInitialTick();

        _kernel = new Kernel();

        _baselineToken = _deployBPOOL(
            _kernel,
            "Base Token",
            "BT",
            _baseTokenDecimals,
            address(_uniV3Factory),
            address(_quoteToken),
            _feeTier,
            _poolInitialTick,
            address(_blast),
            address(0)
        );

        _credt = new CREDTv1(_kernel, address(_blast), address(0));

        _loops = new LOOPSv1(_kernel, 1);

        _bpoolMinter = new BPOOLMinter(_kernel);
        _credtMinter = new CREDTMinter(_kernel);

        _kernel.executeAction(Actions.InstallModule, address(_baselineToken));
        _kernel.executeAction(Actions.ActivatePolicy, address(_bpoolMinter));

        _kernel.executeAction(Actions.InstallModule, address(_credt));
        _kernel.executeAction(Actions.ActivatePolicy, address(_credtMinter));

        _kernel.executeAction(Actions.InstallModule, address(_loops));

        vm.prank(_OWNER);
        _baselineAuctionHouse.installModule(_fpbModule);
        vm.prank(_OWNER);
        _baselineAuctionHouse.installModule(_empModule);

        bytes memory baselineSaltArgs = abi.encodePacked(
            type(BaselineAxisLaunch).creationCode,
            abi.encode(
                address(_baselineAuctionHouse), address(_kernel), address(_quoteToken), _SELLER
            )
        );

        string[] memory baselineInputs = new string[](7);
        baselineInputs[0] = "./test/invariant/helpers/salt_hash.sh";
        baselineInputs[1] = "--bytecodeHash";
        baselineInputs[2] = toHexString(keccak256(baselineSaltArgs));
        baselineInputs[3] = "--prefix";
        baselineInputs[4] = BASELINE_PREFIX;
        baselineInputs[5] = "--deployer";
        baselineInputs[6] = toString(address(this));

        bytes memory baselineRes = vm.ffi(baselineInputs);
        bytes32 baselineSalt = abi.decode(baselineRes, (bytes32));

        _dtlBaseline = new BaselineAxisLaunch{salt: baselineSalt}(
            address(_baselineAuctionHouse), address(_kernel), address(_quoteToken), _SELLER
        );

        _dtlBaselineAddress = address(_dtlBaseline);

        _bpoolMinter.setTransferLock(false);

        _kernel.executeAction(Actions.ActivatePolicy, _dtlBaselineAddress);
    }

    function randomAddress(
        uint256 seed
    ) internal view returns (address) {
        return users[bound(seed, 0, users.length - 1)];
    }

    function randomLotIdV2(
        uint256 seed
    ) internal view returns (uint96) {
        return lotIdsV2[bound(seed, 0, lotIdsV2.length - 1)];
    }

    function randomLotIdV3(
        uint256 seed
    ) internal view returns (uint96) {
        return lotIdsV3[bound(seed, 0, lotIdsV3.length - 1)];
    }

    function _updatePoolInitialTick() internal {
        _poolInitialTick =
            _getTickFromPrice(_fpbParams.price, _baseTokenDecimals, _isBaseTokenAddressLower);
    }

    function _getTickFromPrice(
        uint256 price_,
        uint8 baseTokenDecimals_,
        bool isBaseTokenAddressLower_
    ) internal view returns (int24 tick) {
        // Get sqrtPriceX96
        uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(
            address(_quoteToken),
            isBaseTokenAddressLower_
                ? address(0x0000000000000000000000000000000000000001)
                : address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF),
            price_,
            10 ** baseTokenDecimals_
        );

        // Convert to tick
        return TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    function _deployBPOOL(
        Kernel kernel_,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _factory,
        address _reserve,
        uint24 _feeTier,
        int24 _initialActiveTick,
        address blast,
        address blastGovernor
    ) internal returns (BPOOLv1) {
        bytes32 salt = _getSalt(
            kernel_,
            _name,
            _symbol,
            _decimals,
            _factory,
            _reserve,
            _feeTier,
            _initialActiveTick,
            blast,
            blastGovernor
        );

        return new BPOOLv1{salt: salt}(
            kernel_,
            _name,
            _symbol,
            _decimals,
            _factory,
            _reserve,
            _feeTier,
            _initialActiveTick,
            blast,
            blastGovernor
        );
    }

    // Returns a salt that will result in a BPOOL address less than the reserve address
    function _getSalt(
        Kernel kernel_,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _factory,
        address _reserve,
        uint24 _feeTier,
        int24 _initialActiveTick,
        address blast,
        address blastGovernor
    ) internal view returns (bytes32) {
        uint256 salt;

        while (salt < 100) {
            // Calculate the BPOOL bytecode hash
            bytes32 BPOOLHash = keccak256(
                abi.encodePacked(
                    type(BPOOLv1).creationCode,
                    abi.encode(
                        kernel_,
                        _name,
                        _symbol,
                        _decimals,
                        _factory,
                        _reserve,
                        _feeTier,
                        _initialActiveTick,
                        blast,
                        blastGovernor
                    )
                )
            );

            // Calculate the BPOOL CREATE2 address
            address BPOOLAddress = address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                address(this), // deployer address
                                bytes32(salt),
                                BPOOLHash
                            )
                        )
                    )
                )
            );

            // Return the salt that will result in a BPOOL address less than the reserve address
            if (BPOOLAddress < _reserve) {
                return bytes32(salt);
            }

            salt++;
        }

        revert("No salt found");
    }

    function toString(
        address _addr
    ) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }

        return string(str);
    }

    function givenAddressHasQuoteTokenBalance(address address_, uint256 amount_) internal {
        _quoteToken.mint(address_, amount_);
    }

    function givenAddressHasBaseTokenBalance(address address_, uint256 amount_) internal {
        _baseToken.mint(address_, amount_);
    }

    function givenAddressHasBaselineTokenBalance(address account_, uint256 amount_) internal {
        _baselineToken.mint(account_, amount_);
    }

    function _disableTransferLock() internal {
        _bpoolMinter.setTransferLock(false);
    }

    function _enableTransferLock() internal {
        _bpoolMinter.setTransferLock(true);
    }

    function _transferBaselineTokenRefund(
        uint256 amount_
    ) internal {
        _disableTransferLock();

        // Transfer refund from auction house to the callback
        // We transfer instead of minting to not affect the supply
        vm.prank(address(_baselineAuctionHouse));
        _baselineToken.transfer(_dtlBaselineAddress, amount_);

        _enableTransferLock();
    }

    function givenAddressHasBaseTokenAllowance(
        address owner_,
        address spender_,
        uint256 amount_
    ) internal {
        vm.prank(owner_);
        _baseToken.approve(spender_, type(uint256).max);
    }

    function toHexString(
        bytes32 input
    ) internal pure returns (string memory) {
        bytes16 symbols = "0123456789abcdef";
        bytes memory hex_buffer = new bytes(64 + 2);
        hex_buffer[0] = "0";
        hex_buffer[1] = "x";

        uint256 pos = 2;
        for (uint256 i = 0; i < 32; ++i) {
            uint256 _byte = uint8(input[i]);
            hex_buffer[pos++] = symbols[_byte >> 4];
            hex_buffer[pos++] = symbols[_byte & 0xf];
        }
        return string(hex_buffer);
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
