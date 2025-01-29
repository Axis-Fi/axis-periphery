/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {WithSalts} from "../WithSalts.s.sol";
import {WithDeploySequence} from "../../deploy/WithDeploySequence.s.sol";

// Uniswap
import {UniswapV2DirectToLiquidity} from "../../../src/callbacks/liquidity/UniswapV2DTL.sol";
import {UniswapV3DirectToLiquidity} from "../../../src/callbacks/liquidity/UniswapV3DTL.sol";
import {UniswapV3DTLWithAllocatedAllowlist} from
    "../../../src/callbacks/liquidity/UniswapV3DTLWithAllocatedAllowlist.sol";

contract UniswapDTLSalts is Script, WithDeploySequence, WithSalts {
    string internal constant _ADDRESS_PREFIX = "E6";

    function _setUp(string calldata chain_, string calldata sequenceFilePath_) internal {
        _loadSequence(chain_, sequenceFilePath_);
        _createBytecodeDirectory();
    }

    function generate(string calldata chain_, string calldata deployFilePath_) public {
        _setUp(chain_, deployFilePath_);

        // Iterate over the deployment sequence
        string[] memory sequenceNames = _getSequenceNames();
        for (uint256 i; i < sequenceNames.length; i++) {
            string memory sequenceName = sequenceNames[i];
            console2.log("");
            console2.log("Generating salt for :", sequenceName);

            string memory deploymentKey = _getDeploymentKey(sequenceName);
            console2.log("    deploymentKey: %s", deploymentKey);

            // Atomic Uniswap V2
            if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("AtomicUniswapV2DirectToLiquidity"))
            ) {
                address auctionHouse = _envAddressNotZero("deployments.AtomicAuctionHouse");

                _generateV2(sequenceName, auctionHouse, deploymentKey);
            }
            // Batch Uniswap V2
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchUniswapV2DirectToLiquidity"))
            ) {
                address auctionHouse = _envAddressNotZero("deployments.BatchAuctionHouse");

                _generateV2(sequenceName, auctionHouse, deploymentKey);
            }
            // Atomic Uniswap V3
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("AtomicUniswapV3DirectToLiquidity"))
            ) {
                address auctionHouse = _envAddressNotZero("deployments.AtomicAuctionHouse");

                _generateV3(sequenceName, auctionHouse, deploymentKey);
            }
            // Batch Uniswap V3
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchUniswapV3DirectToLiquidity"))
            ) {
                address auctionHouse = _envAddressNotZero("deployments.BatchAuctionHouse");

                _generateV3(sequenceName, auctionHouse, deploymentKey);
            }
            // Batch Uniswap V3 with Allocated Allowlist
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(
                        abi.encodePacked("BatchUniswapV3DirectToLiquidityWithAllocatedAllowlist")
                    )
            ) {
                address auctionHouse = _envAddressNotZero("deployments.BatchAuctionHouse");

                _generateV3(sequenceName, auctionHouse, deploymentKey);
            }
            // Something else
            else {
                console2.log("    Skipping unknown sequence: %s", sequenceName);
            }
        }
    }

    function _generateV2(
        string memory sequenceName_,
        address auctionHouse_,
        string memory deploymentKey_
    ) internal {
        // Get input variables or overrides
        address envUniswapV2Factory =
            _getEnvAddressOrOverride("constants.uniswapV2.factory", sequenceName_, "args.factory");
        address envUniswapV2Router =
            _getEnvAddressOrOverride("constants.uniswapV2.router", sequenceName_, "args.router");

        // Calculate salt for the UniswapV2DirectToLiquidity
        bytes memory contractCode = type(UniswapV2DirectToLiquidity).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
            deploymentKey_,
            contractCode,
            abi.encode(auctionHouse_, envUniswapV2Factory, envUniswapV2Router)
        );
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }

    function _generateV3(
        string memory sequenceName_,
        address auctionHouse_,
        string memory deploymentKey_
    ) internal {
        // Get input variables or overrides
        address envUniswapV3Factory = _getEnvAddressOrOverride(
            "constants.uniswapV3.factory", sequenceName_, "args.uniswapV3Factory"
        );
        address envGUniFactory =
            _getEnvAddressOrOverride("constants.gUni.factory", sequenceName_, "args.gUniFactory");

        // Calculate salt for the UniswapV2DirectToLiquidity
        bytes memory contractCode = type(UniswapV3DirectToLiquidity).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
            deploymentKey_,
            contractCode,
            abi.encode(auctionHouse_, envUniswapV3Factory, envGUniFactory)
        );
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }

    function _generateV3WithAllocatedAllowlist(
        string memory sequenceName_,
        address auctionHouse_,
        string memory deploymentKey_
    ) internal {
        // Get input variables or overrides
        address envUniswapV3Factory = _getEnvAddressOrOverride(
            "constants.uniswapV3.factory", sequenceName_, "args.uniswapV3Factory"
        );
        address envGUniFactory =
            _getEnvAddressOrOverride("constants.gUni.factory", sequenceName_, "args.gUniFactory");

        // Calculate salt for the UniswapV2DirectToLiquidity
        bytes memory contractCode = type(UniswapV3DTLWithAllocatedAllowlist).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
            deploymentKey_,
            contractCode,
            abi.encode(auctionHouse_, envUniswapV3Factory, envGUniFactory)
        );
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }
}
