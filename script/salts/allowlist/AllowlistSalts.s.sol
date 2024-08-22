/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {WithSalts} from "../WithSalts.s.sol";
import {WithDeploySequence} from "../../deploy/WithDeploySequence.s.sol";

// Libraries
import {Callbacks} from "@axis-core-1.0.1/lib/Callbacks.sol";

// Callbacks
import {MerkleAllowlist} from "../../../src/callbacks/allowlists/MerkleAllowlist.sol";
import {CappedMerkleAllowlist} from "../../../src/callbacks/allowlists/CappedMerkleAllowlist.sol";
import {TokenAllowlist} from "../../../src/callbacks/allowlists/TokenAllowlist.sol";
import {AllocatedMerkleAllowlist} from
    "../../../src/callbacks/allowlists/AllocatedMerkleAllowlist.sol";

contract AllowlistSalts is Script, WithDeploySequence, WithSalts {
    // All of these allowlists have the same permissions and constructor args
    string internal constant _ADDRESS_PREFIX = "98";

    function _setUp(string calldata chain_, string calldata sequenceFilePath_) internal {
        _loadSequence(chain_, sequenceFilePath_);
        _createBytecodeDirectory();
    }

    function _getContractArgs(address auctionHouse_) internal pure returns (bytes memory) {
        return abi.encode(
            auctionHouse_,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: true,
                onBid: true,
                onSettle: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            })
        );
    }

    function _getAuctionHouse(bool atomic_) internal view returns (address) {
        return atomic_
            ? _envAddressNotZero("deployments.AtomicAuctionHouse")
            : _envAddressNotZero("deployments.BatchAuctionHouse");
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

            // Atomic MerkleAllowlist
            if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("AtomicMerkleAllowlist"))
            ) {
                _generateMerkleAllowlist(sequenceName, deploymentKey, true);
            }
            // Batch MerkleAllowlist
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchMerkleAllowlist"))
            ) {
                _generateMerkleAllowlist(sequenceName, deploymentKey, false);
            }
            // Atomic CappedMerkleAllowlist
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("AtomicCappedMerkleAllowlist"))
            ) {
                _generateCappedMerkleAllowlist(sequenceName, deploymentKey, true);
            }
            // Batch CappedMerkleAllowlist
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchCappedMerkleAllowlist"))
            ) {
                _generateCappedMerkleAllowlist(sequenceName, deploymentKey, false);
            }
            // Atomic AllocatedMerkleAllowlist
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("AtomicAllocatedMerkleAllowlist"))
            ) {
                _generateAllocatedMerkleAllowlist(sequenceName, deploymentKey, true);
            }
            // Batch AllocatedMerkleAllowlist
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchAllocatedMerkleAllowlist"))
            ) {
                _generateAllocatedMerkleAllowlist(sequenceName, deploymentKey, false);
            }
            // Atomic TokenAllowlist
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("AtomicTokenAllowlist"))
            ) {
                _generateTokenAllowlist(sequenceName, deploymentKey, true);
            }
            // Batch TokenAllowlist
            else if (
                keccak256(abi.encodePacked(sequenceName))
                    == keccak256(abi.encodePacked("BatchTokenAllowlist"))
            ) {
                _generateTokenAllowlist(sequenceName, deploymentKey, false);
            }
            // Something else
            else {
                console2.log("    Skipping unknown sequence: %s", sequenceName);
            }
        }
    }

    function _generateMerkleAllowlist(
        string memory,
        string memory deploymentKey_,
        bool atomic_
    ) internal {
        bytes memory contractCode = type(MerkleAllowlist).creationCode;
        bytes memory contractArgs = _getContractArgs(_getAuctionHouse(atomic_));

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey_, contractCode, contractArgs);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }

    function _generateCappedMerkleAllowlist(
        string memory,
        string memory deploymentKey_,
        bool atomic_
    ) internal {
        bytes memory contractCode = type(CappedMerkleAllowlist).creationCode;
        bytes memory contractArgs = _getContractArgs(_getAuctionHouse(atomic_));

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey_, contractCode, contractArgs);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }

    function _generateAllocatedMerkleAllowlist(
        string memory,
        string memory deploymentKey_,
        bool atomic_
    ) internal {
        bytes memory contractCode = type(AllocatedMerkleAllowlist).creationCode;
        bytes memory contractArgs = _getContractArgs(_getAuctionHouse(atomic_));

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey_, contractCode, contractArgs);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }

    function _generateTokenAllowlist(
        string memory,
        string memory deploymentKey_,
        bool atomic_
    ) internal {
        bytes memory contractCode = type(TokenAllowlist).creationCode;
        bytes memory contractArgs = _getContractArgs(_getAuctionHouse(atomic_));

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey_, contractCode, contractArgs);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey_, bytecodeHash);
    }
}
