/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {WithSalts} from "../WithSalts.s.sol";
import {WithDeploySequence} from "../../deploy/WithDeploySequence.s.sol";

// Ramses
import {RamsesV1DirectToLiquidity} from "../../../src/callbacks/liquidity/Ramses/RamsesV1DTL.sol";
import {RamsesV2DirectToLiquidity} from "../../../src/callbacks/liquidity/Ramses/RamsesV2DTL.sol";

contract RamsesDTLSalts is Script, WithDeploySequence, WithSalts {
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

            // Atomic Ramses V1
            if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("AtomicRamsesV1DirectToLiquidity"))
            ) {
                address auctionHouse = _envAddressNotZero("deployments.AtomicAuctionHouse");

                _generateV1(sequenceName, auctionHouse, deploymentKey);
            }
            // Batch Ramses V1
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchRamsesV1DirectToLiquidity"))
            ) {
                address auctionHouse = _envAddressNotZero("deployments.BatchAuctionHouse");

                _generateV1(sequenceName, auctionHouse, deploymentKey);
            }
            // Atomic Ramses V2
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("AtomicRamsesV2DirectToLiquidity"))
            ) {
                address auctionHouse = _envAddressNotZero("deployments.AtomicAuctionHouse");

                _generateV2(sequenceName, auctionHouse, deploymentKey);
            }
            // Batch Ramses V2
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchRamsesV2DirectToLiquidity"))
            ) {
                address auctionHouse = _envAddressNotZero("deployments.BatchAuctionHouse");

                _generateV2(sequenceName, auctionHouse, deploymentKey);
            }
            // Something else
            else {
                console2.log("    Skipping unknown sequence: %s", sequenceName);
            }
        }
    }

    function _generateV1(
        string memory sequenceName_,
        address auctionHouse_,
        string memory deploymentKey_
    ) internal {
        // Get input variables or overrides
        address envRamsesV1PairFactory = _getEnvAddressOrOverride(
            "constants.ramsesV1.pairFactory", sequenceName_, "args.pairFactory"
        );
        address envRamsesV1Router =
            _getEnvAddressOrOverride("constants.ramsesV1.router", sequenceName_, "args.router");

        // Calculate salt for the RamsesV1DirectToLiquidity
        bytes memory contractCode = type(RamsesV1DirectToLiquidity).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
            deploymentKey_,
            contractCode,
            abi.encode(auctionHouse_, envRamsesV1PairFactory, envRamsesV1Router)
        );
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }

    function _generateV2(
        string memory sequenceName_,
        address auctionHouse_,
        string memory deploymentKey_
    ) internal {
        // Get input variables or overrides
        address envRamsesV2Factory =
            _getEnvAddressOrOverride("constants.ramsesV2.factory", sequenceName_, "args.factory");
        address envRamsesV2PositionManager = _getEnvAddressOrOverride(
            "constants.ramsesV2.positionManager", sequenceName_, "args.positionManager"
        );

        // Calculate salt for the RamsesV2DirectToLiquidity
        bytes memory contractCode = type(RamsesV2DirectToLiquidity).creationCode;
        (string memory bytecodePath, bytes32 bytecodeHash) = _writeBytecode(
            deploymentKey_,
            contractCode,
            abi.encode(auctionHouse_, envRamsesV2Factory, envRamsesV2PositionManager)
        );
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }
}
