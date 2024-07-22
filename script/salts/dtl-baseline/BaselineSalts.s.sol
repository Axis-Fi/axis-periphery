/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {WithSalts} from "../WithSalts.s.sol";
import {WithDeploySequence} from "../../deploy/WithDeploySequence.s.sol";

import {BaselineAxisLaunch} from
    "../../../src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {BALwithAllocatedAllowlist} from
    "../../../src/callbacks/liquidity/BaselineV2/BALwithAllocatedAllowlist.sol";
import {BALwithAllowlist} from "../../../src/callbacks/liquidity/BaselineV2/BALwithAllowlist.sol";
import {BALwithCappedAllowlist} from
    "../../../src/callbacks/liquidity/BaselineV2/BALwithCappedAllowlist.sol";
import {BALwithTokenAllowlist} from
    "../../../src/callbacks/liquidity/BaselineV2/BALwithTokenAllowlist.sol";

contract BaselineSalts is Script, WithDeploySequence, WithSalts {
    string internal constant _ADDRESS_PREFIX = "EF";

    address internal _envBatchAuctionHouse;

    function _isDefaultDeploymentKey(string memory str) internal pure returns (bool) {
        // If the string is "DEFAULT", it's the default deployment key
        return keccak256(abi.encode(str)) == keccak256(abi.encode("DEFAULT"));
    }

    function _setUp(string calldata chain_, string calldata sequenceFilePath_) internal {
        _loadSequence(chain_, sequenceFilePath_);
        _createBytecodeDirectory();

        // Cache auction houses
        _envBatchAuctionHouse = _envAddressNotZero("deployments.BatchAuctionHouse");
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

            // BaselineAxisLaunch
            if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchBaselineAxisLaunch"))
            ) {
                _generateBaselineAxisLaunch(sequenceName, deploymentKey);
            }
            // BaselineAllocatedAllowlist
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchBaselineAllocatedAllowlist"))
            ) {
                _generateBaselineAllocatedAllowlist(sequenceName, deploymentKey);
            }
            // BaselineAllowlist
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchBaselineAllowlist"))
            ) {
                _generateBaselineAllowlist(sequenceName, deploymentKey);
            }
            // BaselineCappedAllowlist
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchBaselineCappedAllowlist"))
            ) {
                _generateBaselineCappedAllowlist(sequenceName, deploymentKey);
            }
            // BaselineTokenAllowlist
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchBaselineTokenAllowlist"))
            ) {
                _generateBaselineTokenAllowlist(sequenceName, deploymentKey);
            }
            // Something else
            else {
                console2.log("    Skipping unknown sequence: %s", sequenceName);
            }
        }
    }

    function _generateBaselineAxisLaunch(
        string memory sequenceName_,
        string memory deploymentKey_
    ) internal {
        bytes memory contractCode = type(BaselineAxisLaunch).creationCode;
        bytes memory contractArgs_ = abi.encode(
            _envBatchAuctionHouse,
            _getSequenceAddress(sequenceName_, "args.baselineKernel"),
            _getSequenceAddress(sequenceName_, "args.reserveToken"),
            _getSequenceAddress(sequenceName_, "args.baselineOwner")
        );

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey_, contractCode, contractArgs_);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }

    function _generateBaselineAllocatedAllowlist(
        string memory sequenceName_,
        string memory deploymentKey_
    ) internal {
        bytes memory contractCode = type(BALwithAllocatedAllowlist).creationCode;
        bytes memory contractArgs_ = abi.encode(
            _envBatchAuctionHouse,
            _getSequenceAddress(sequenceName_, "args.baselineKernel"),
            _getSequenceAddress(sequenceName_, "args.reserveToken"),
            _getSequenceAddress(sequenceName_, "args.baselineOwner")
        );

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey_, contractCode, contractArgs_);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }

    function _generateBaselineAllowlist(
        string memory sequenceName_,
        string memory deploymentKey_
    ) internal {
        bytes memory contractCode = type(BALwithAllowlist).creationCode;
        bytes memory contractArgs_ = abi.encode(
            _envBatchAuctionHouse,
            _getSequenceAddress(sequenceName_, "args.baselineKernel"),
            _getSequenceAddress(sequenceName_, "args.reserveToken"),
            _getSequenceAddress(sequenceName_, "args.baselineOwner")
        );

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey_, contractCode, contractArgs_);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }

    function _generateBaselineCappedAllowlist(
        string memory sequenceName_,
        string memory deploymentKey_
    ) internal {
        bytes memory contractCode = type(BALwithCappedAllowlist).creationCode;
        bytes memory contractArgs_ = abi.encode(
            _envBatchAuctionHouse,
            _getSequenceAddress(sequenceName_, "args.baselineKernel"),
            _getSequenceAddress(sequenceName_, "args.reserveToken"),
            _getSequenceAddress(sequenceName_, "args.baselineOwner")
        );

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey_, contractCode, contractArgs_);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }

    function _generateBaselineTokenAllowlist(
        string memory sequenceName_,
        string memory deploymentKey_
    ) internal {
        bytes memory contractCode = type(BALwithTokenAllowlist).creationCode;
        bytes memory contractArgs_ = abi.encode(
            _envBatchAuctionHouse,
            _getSequenceAddress(sequenceName_, "args.baselineKernel"),
            _getSequenceAddress(sequenceName_, "args.reserveToken"),
            _getSequenceAddress(sequenceName_, "args.baselineOwner")
        );

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey_, contractCode, contractArgs_);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }
}
