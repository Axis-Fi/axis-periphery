/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script} from "@forge-std-1.9.1/Script.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";
import {WithEnvironment} from "../../deploy/WithEnvironment.s.sol";
import {WithSalts} from "../WithSalts.s.sol";
import {TestConstants} from "../../../test/Constants.sol";

// Libraries
import {Permit2User} from "@axis-core-1.0.4-test/lib/permit2/Permit2User.sol";
import {Callbacks} from "@axis-core-1.0.4/lib/Callbacks.sol";
import {MockERC20} from "@solmate-6.8.0/test/utils/mocks/MockERC20.sol";

// Uniswap
import {UniswapV3Factory} from "../../../test/lib/uniswap-v3/UniswapV3Factory.sol";
import {GUniFactory} from "@g-uni-v1-core-0.9.9/GUniFactory.sol";
import {UniswapV2Router02} from "@uniswap-v2-periphery-1.0.1/UniswapV2Router02.sol";

// Callbacks
import {CappedMerkleAllowlist} from "../../../src/callbacks/allowlists/CappedMerkleAllowlist.sol";
import {AllocatedMerkleAllowlist} from
    "../../../src/callbacks/allowlists/AllocatedMerkleAllowlist.sol";
import {TokenAllowlist} from "../../../src/callbacks/allowlists/TokenAllowlist.sol";
import {UniswapV2DirectToLiquidity} from "../../../src/callbacks/liquidity/UniswapV2DTL.sol";
import {UniswapV3DirectToLiquidity} from "../../../src/callbacks/liquidity/UniswapV3DTL.sol";

// import {BaselineAxisLaunch} from
//     "../../../src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
// import {BALwithAllocatedAllowlist} from
//     "../../../src/callbacks/liquidity/BaselineV2/BALwithAllocatedAllowlist.sol";
// import {BALwithAllowlist} from "../../../src/callbacks/liquidity/BaselineV2/BALwithAllowlist.sol";
// import {BALwithCappedAllowlist} from
//     "../../../src/callbacks/liquidity/BaselineV2/BALwithCappedAllowlist.sol";
// import {BALwithTokenAllowlist} from
//     "../../../src/callbacks/liquidity/BaselineV2/BALwithTokenAllowlist.sol";

contract TestSalts is Script, WithEnvironment, Permit2User, WithSalts, TestConstants {
    string internal constant _CAPPED_MERKLE_ALLOWLIST = "CappedMerkleAllowlist";
    string internal constant _ALLOCATED_MERKLE_ALLOWLIST = "AllocatedMerkleAllowlist";
    string internal constant _TOKEN_ALLOWLIST = "TokenAllowlist";

    function _setUp(
        string calldata chain_
    ) internal {
        _loadEnv(chain_);
        _createBytecodeDirectory();
    }

    function generate(string calldata chain_, string calldata saltKey_) public {
        _setUp(chain_);

        // For the given salt key, call the appropriate selector
        // e.g. a salt key named MockCallback would require the following function: generateMockCallback()
        bytes4 selector = bytes4(keccak256(bytes(string.concat("generate", saltKey_, "()"))));

        // Call the generate function for the salt key
        (bool success,) = address(this).call(abi.encodeWithSelector(selector));
        require(success, string.concat("Failed to generate ", saltKey_));
    }

    function generateUniswapV2DirectToLiquidity() public {
        bytes memory args = abi.encode(_AUCTION_HOUSE, _UNISWAP_V2_FACTORY, _UNISWAP_V2_ROUTER);
        bytes memory contractCode = type(UniswapV2DirectToLiquidity).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode("UniswapV2DirectToLiquidity", contractCode, args);
        _setTestSalt(bytecodePath, "E6", "UniswapV2DirectToLiquidity", bytecodeHash);
    }

    function generateUniswapV3DirectToLiquidity() public {
        bytes memory args = abi.encode(_AUCTION_HOUSE, _UNISWAP_V3_FACTORY, _GUNI_FACTORY);
        bytes memory contractCode = type(UniswapV3DirectToLiquidity).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode("UniswapV3DirectToLiquidity", contractCode, args);
        _setTestSalt(bytecodePath, "E6", "UniswapV3DirectToLiquidity", bytecodeHash);
    }

    function generateGUniFactory() public {
        // Generate a salt for a GUniFactory
        bytes memory args = abi.encode(_UNISWAP_V3_FACTORY);
        bytes memory contractCode = type(GUniFactory).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode("GUniFactory", contractCode, args);
        _setTestSaltWithDeployer(bytecodePath, "AA", "GUniFactory", bytecodeHash, _CREATE2_DEPLOYER);

        // Fetch the salt that was set
        bytes32 gUniFactorySalt = _getSalt("Test_GUniFactory", contractCode, args);

        // Get the address of the GUniFactory
        // Update the `_GUNI_FACTORY` constant with this value
        vm.prank(_CREATE2_DEPLOYER);
        GUniFactory gUniFactory = new GUniFactory{salt: gUniFactorySalt}(_UNISWAP_V3_FACTORY);
        console2.log("GUniFactory address: ", address(gUniFactory));
    }

    function generateUniswapV3Factory() public {
        // Generate a salt for a GUniFactory
        bytes memory args = abi.encode();
        bytes memory contractCode = type(UniswapV3Factory).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode("UniswapV3Factory", contractCode, args);
        _setTestSaltWithDeployer(
            bytecodePath, "AA", "UniswapV3Factory", bytecodeHash, _CREATE2_DEPLOYER
        );

        // Fetch the salt that was set
        bytes32 uniswapV3FactorySalt = _getSalt("Test_UniswapV3Factory", contractCode, args);

        // Get the address of the UniswapV3Factory
        // Update the `_UNISWAP_V3_FACTORY` constant with this value
        vm.prank(_CREATE2_DEPLOYER);
        UniswapV3Factory uniswapV3Factory = new UniswapV3Factory{salt: uniswapV3FactorySalt}();
        console2.log("UniswapV3Factory address: ", address(uniswapV3Factory));
    }

    function generateBaselineQuoteToken() public {
        // Generate a salt for a MockERC20 quote token
        bytes memory qtArgs = abi.encode("Quote Token", "QT", 18);
        bytes memory qtContractCode = type(MockERC20).creationCode;
        (string memory qtBytecodePath, bytes32 qtBytecodeHash) =
            _writeBytecode("QuoteToken", qtContractCode, qtArgs);
        _setTestSaltWithDeployer(
            qtBytecodePath, "AA", "QuoteToken", qtBytecodeHash, _CREATE2_DEPLOYER
        );

        // Fetch the salt that was set
        bytes32 quoteTokenSalt = _getSalt("Test_QuoteToken", qtContractCode, qtArgs);

        // Get the address of the quote token
        // Update the `_BASELINE_QUOTE_TOKEN` constants with this value
        vm.prank(_CREATE2_DEPLOYER);
        MockERC20 quoteToken = new MockERC20{salt: quoteTokenSalt}("Quote Token", "QT", 18);
        console2.log("Quote Token address: ", address(quoteToken));
    }

    // function generateBaselineAxisLaunch() public {
    //     // Get the salt
    //     bytes memory callbackArgs =
    //         abi.encode(_AUCTION_HOUSE, _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN, _SELLER);
    //     (string memory callbackBytecodePath, bytes32 callbackBytecodeHash) = _writeBytecode(
    //         "BaselineAxisLaunch", type(BaselineAxisLaunch).creationCode, callbackArgs
    //     );
    //     _setTestSalt(callbackBytecodePath, "EF", "BaselineAxisLaunch", callbackBytecodeHash);
    // }

    // function generateBaselineAllocatedAllowlist() public {
    //     // Get the salt
    //     bytes memory callbackArgs =
    //         abi.encode(_AUCTION_HOUSE, _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN, _SELLER);
    //     (string memory callbackBytecodePath, bytes32 callbackBytecodeHash) = _writeBytecode(
    //         "BaselineAllocatedAllowlist", type(BALwithAllocatedAllowlist).creationCode, callbackArgs
    //     );
    //     _setTestSalt(callbackBytecodePath, "EF", "BaselineAllocatedAllowlist", callbackBytecodeHash);
    // }

    // function generateBaselineAllowlist() public {
    //     // Get the salt
    //     bytes memory callbackArgs =
    //         abi.encode(_AUCTION_HOUSE, _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN, _SELLER);
    //     (string memory callbackBytecodePath, bytes32 callbackBytecodeHash) =
    //         _writeBytecode("BaselineAllowlist", type(BALwithAllowlist).creationCode, callbackArgs);
    //     _setTestSalt(callbackBytecodePath, "EF", "BaselineAllowlist", callbackBytecodeHash);
    // }

    // function generateBaselineCappedAllowlist() public {
    //     // Get the salt
    //     bytes memory callbackArgs =
    //         abi.encode(_AUCTION_HOUSE, _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN, _SELLER);
    //     (string memory callbackBytecodePath, bytes32 callbackBytecodeHash) = _writeBytecode(
    //         "BaselineCappedAllowlist", type(BALwithCappedAllowlist).creationCode, callbackArgs
    //     );
    //     _setTestSalt(callbackBytecodePath, "EF", "BaselineCappedAllowlist", callbackBytecodeHash);
    // }

    // function generateBaselineTokenAllowlist() public {
    //     // Get the salt
    //     bytes memory callbackArgs =
    //         abi.encode(_AUCTION_HOUSE, _BASELINE_KERNEL, _BASELINE_QUOTE_TOKEN, _SELLER);
    //     (string memory callbackBytecodePath, bytes32 callbackBytecodeHash) = _writeBytecode(
    //         "BaselineTokenAllowlist", type(BALwithTokenAllowlist).creationCode, callbackArgs
    //     );
    //     _setTestSalt(callbackBytecodePath, "EF", "BaselineTokenAllowlist", callbackBytecodeHash);
    // }
}
