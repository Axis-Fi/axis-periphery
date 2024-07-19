/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {WithEnvironment} from "../../deploy/WithEnvironment.s.sol";
import {WithSalts} from "../WithSalts.s.sol";

// Uniswap
import {UniswapV2DirectToLiquidity} from "../../../src/callbacks/liquidity/UniswapV2DTL.sol";
import {UniswapV3DirectToLiquidity} from "../../../src/callbacks/liquidity/UniswapV3DTL.sol";

contract UniswapDTLSalts is Script, WithEnvironment, WithSalts {
    string internal constant _ADDRESS_PREFIX = "E6";

    address internal _envUniswapV2Factory;
    address internal _envUniswapV2Router;
    address internal _envUniswapV3Factory;
    address internal _envGUniFactory;

    function _isDefaultDeploymentKey(string memory str) internal pure returns (bool) {
        // If the string is "DEFAULT", it's the default deployment key
        return keccak256(abi.encode(str)) == keccak256(abi.encode("DEFAULT"));
    }

    function _setUp(string calldata chain_) internal {
        _loadEnv(chain_);
        _createBytecodeDirectory();

        // Cache Uniswap factories
        _envUniswapV2Factory = _envAddressNotZero("constants.uniswapV2.factory");
        _envUniswapV2Router = _envAddressNotZero("constants.uniswapV2.router");
        _envUniswapV3Factory = _envAddressNotZero("constants.uniswapV3.factory");
        _envGUniFactory = _envAddressNotZero("constants.gUni.factory");
    }

    function generate(
        string calldata chain_,
        string calldata uniswapVersion_,
        string calldata deploymentKey_,
        bool atomic_
    ) public {
        _setUp(chain_);

        if (keccak256(abi.encodePacked(uniswapVersion_)) == keccak256(abi.encodePacked("2"))) {
            _generateV2(atomic_, deploymentKey_);
        } else if (keccak256(abi.encodePacked(uniswapVersion_)) == keccak256(abi.encodePacked("3")))
        {
            _generateV3(atomic_, deploymentKey_);
        } else {
            revert("Invalid Uniswap version: 2 or 3");
        }
    }

    function _generateV2(bool atomic_, string calldata deploymentKey_) internal {
        string memory deploymentKey =
            _isDefaultDeploymentKey(deploymentKey_) ? "UniswapV2DirectToLiquidity" : deploymentKey_;
        console2.log("    deploymentKey: %s", deploymentKey);

        if (atomic_) {
            address _envAtomicAuctionHouse = _envAddressNotZero("deployments.AtomicAuctionHouse");

            // Calculate salt for the UniswapV2DirectToLiquidity
            bytes memory contractCode = type(UniswapV2DirectToLiquidity).creationCode;
            (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
                deploymentKey,
                contractCode,
                abi.encode(_envAtomicAuctionHouse, _envUniswapV2Factory, _envUniswapV2Router)
            );
            _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey, bytecodeHash);
        } else {
            address _envBatchAuctionHouse = _envAddressNotZero("deployments.BatchAuctionHouse");

            // Calculate salt for the UniswapV2DirectToLiquidity
            bytes memory contractCode = type(UniswapV2DirectToLiquidity).creationCode;
            (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
                deploymentKey,
                contractCode,
                abi.encode(_envBatchAuctionHouse, _envUniswapV2Factory, _envUniswapV2Router)
            );
            _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey, bytecodeHash);
        }
    }

    function _generateV3(bool atomic_, string calldata deploymentKey_) internal {
        string memory deploymentKey =
            _isDefaultDeploymentKey(deploymentKey_) ? "UniswapV2DirectToLiquidity" : deploymentKey_;
        console2.log("    deploymentKey: %s", deploymentKey);

        if (atomic_) {
            address _envAtomicAuctionHouse = _envAddressNotZero("deployments.AtomicAuctionHouse");

            // Calculate salt for the UniswapV3DirectToLiquidity
            bytes memory contractCode = type(UniswapV3DirectToLiquidity).creationCode;
            (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
                deploymentKey,
                contractCode,
                abi.encode(_envAtomicAuctionHouse, _envUniswapV3Factory, _envGUniFactory)
            );
            _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey, bytecodeHash);
        } else {
            address _envBatchAuctionHouse = _envAddressNotZero("deployments.BatchAuctionHouse");

            // Calculate salt for the UniswapV3DirectToLiquidity
            bytes memory contractCode = type(UniswapV3DirectToLiquidity).creationCode;
            (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
                deploymentKey,
                contractCode,
                abi.encode(_envBatchAuctionHouse, _envUniswapV3Factory, _envGUniFactory)
            );
            _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey, bytecodeHash);
        }
    }
}
