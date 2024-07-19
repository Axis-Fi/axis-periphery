/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {WithEnvironment} from "../../deploy/WithEnvironment.s.sol";
import {WithSalts} from "../WithSalts.s.sol";

// Libraries
import {Callbacks} from "@axis-core-1.0.0/lib/Callbacks.sol";

// Callbacks
import {MerkleAllowlist} from "../../../src/callbacks/allowlists/MerkleAllowlist.sol";
import {CappedMerkleAllowlist} from "../../../src/callbacks/allowlists/CappedMerkleAllowlist.sol";
import {TokenAllowlist} from "../../../src/callbacks/allowlists/TokenAllowlist.sol";
import {AllocatedMerkleAllowlist} from
    "../../../src/callbacks/allowlists/AllocatedMerkleAllowlist.sol";

contract AllowlistSalts is Script, WithEnvironment, WithSalts {
    string internal constant _ADDRESS_PREFIX = "98";

    function _isDefaultDeploymentKey(string memory str) internal pure returns (bool) {
        // If the string is "DEFAULT", it's the default deployment key
        return keccak256(abi.encode(str)) == keccak256(abi.encode("DEFAULT"));
    }

    function _setUp(string calldata chain_) internal {
        _loadEnv(chain_);
        _createBytecodeDirectory();
    }

    function generate(
        string calldata chain_,
        string calldata deploymentKeySuffix_,
        bool atomic_
    ) public {
        _setUp(chain_);

        address auctionHouse;
        string memory deploymentKeyPrefix;
        if (atomic_) {
            auctionHouse = _envAddress("deployments.AtomicAuctionHouse");
            deploymentKeyPrefix = "Atomic";
        } else {
            auctionHouse = _envAddress("deployments.BatchAuctionHouse");
            deploymentKeyPrefix = "Batch";
        }

        string memory deploymentKeySuffix =
            _isDefaultDeploymentKey(deploymentKeySuffix_) ? "" : deploymentKeySuffix_;
        console2.log("    deploymentKeySuffix: %s", deploymentKeySuffix);

        // All of these allowlists have the same permissions and constructor args
        string memory prefix = "98";
        bytes memory args = abi.encode(
            auctionHouse,
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

        // Merkle Allowlist
        // 10011000 = 0x98
        bytes memory contractCode = type(MerkleAllowlist).creationCode;
        string memory saltKey =
            string.concat(deploymentKeyPrefix, "MerkleAllowlist", deploymentKeySuffix);
        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(saltKey, contractCode, args);
        _setSalt(bytecodePath, prefix, saltKey, bytecodeHash);

        // Capped Merkle Allowlist
        // 10011000 = 0x98
        contractCode = type(CappedMerkleAllowlist).creationCode;
        saltKey = string.concat(deploymentKeyPrefix, "CappedMerkleAllowlist", deploymentKeySuffix);
        (bytecodePath, bytecodeHash) = _writeBytecode(saltKey, contractCode, args);
        _setSalt(bytecodePath, prefix, saltKey, bytecodeHash);

        // Token Allowlist
        // 10011000 = 0x98
        contractCode = type(TokenAllowlist).creationCode;
        saltKey = string.concat(deploymentKeyPrefix, "TokenAllowlist", deploymentKeySuffix);
        (bytecodePath, bytecodeHash) = _writeBytecode(saltKey, contractCode, args);
        _setSalt(bytecodePath, prefix, saltKey, bytecodeHash);

        // Allocated Allowlist
        contractCode = type(AllocatedMerkleAllowlist).creationCode;
        saltKey =
            string.concat(deploymentKeyPrefix, "AllocatedMerkleAllowlist", deploymentKeySuffix);
        (bytecodePath, bytecodeHash) = _writeBytecode(saltKey, contractCode, args);
        _setSalt(bytecodePath, prefix, saltKey, bytecodeHash);
    }
}
