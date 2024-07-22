// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {stdJson} from "@forge-std-1.9.1/StdJson.sol";

import {WithEnvironment} from "./WithEnvironment.s.sol";

/// @notice A script that loads a deployment sequence from a JSON file
/// @dev    This script loads a deployment sequence from a JSON file, and provides helper functions to access values from it
abstract contract WithDeploySequence is Script, WithEnvironment {
    using stdJson for string;

    string internal _sequenceJson;

    function _loadSequence(
        string calldata chain_,
        string calldata sequenceFilePath_
    ) internal virtual {
        _loadEnv(chain_);

        // Load deployment data
        _sequenceJson = vm.readFile(sequenceFilePath_);
    }

    // === Higher-level script functions === //

    function _getDeploymentKey(string memory sequenceName_) internal view returns (string memory) {
        return string.concat(
            sequenceName_, _getSequenceStringOrFallback(sequenceName_, "deploymentKeySuffix", "")
        );
    }

    /// @notice Obtains an address value from the deployment sequence (if it exists), or the env.json as a fallback
    function _getEnvAddressOrOverride(
        string memory envKey_,
        string memory sequenceName_,
        string memory key_
    ) internal view returns (address) {
        // Check if the key is set in the deployment sequence
        if (_sequenceKeyExists(sequenceName_, key_)) {
            address sequenceAddress = _getSequenceAddress(sequenceName_, key_);
            console2.log("    %s: %s (from deployment sequence)", envKey_, sequenceAddress);
            return sequenceAddress;
        }

        // Otherwsie return from the environment variables
        return _envAddressNotZero(envKey_);
    }

    // === Low-level JSON functions === //

    /// @notice Construct a key to access a value in the deployment sequence
    function _getSequenceKey(
        string memory name_,
        string memory key_
    ) internal pure returns (string memory) {
        return string.concat(".sequence[?(@.name == '", name_, "')].", key_);
    }

    /// @notice Determines if a key exists in the deployment sequence
    function _sequenceKeyExists(
        string memory name_,
        string memory key_
    ) internal view returns (bool) {
        return vm.keyExists(_sequenceJson, _getSequenceKey(name_, key_));
    }

    /// @notice Obtains a string value from the given key in the deployment sequence
    /// @dev    This will revert if the key does not exist
    function _getSequenceString(
        string memory name_,
        string memory key_
    ) internal view returns (string memory) {
        return vm.parseJsonString(_sequenceJson, _getSequenceKey(name_, key_));
    }

    /// @notice Obtains a string value from the deployment sequence (if it exists), or a fallback value
    function _getSequenceStringOrFallback(
        string memory name_,
        string memory key_,
        string memory fallbackValue_
    ) internal view returns (string memory) {
        // Check if the key is set in the deployment sequence
        if (_sequenceKeyExists(name_, key_)) {
            return _getSequenceString(name_, key_);
        }

        // Otherwise, return the fallback value
        return fallbackValue_;
    }

    /// @notice Obtains an address value from the given key in the deployment sequence
    /// @dev    This will revert if the key does not exist
    function _getSequenceAddress(
        string memory name_,
        string memory key_
    ) internal view returns (address) {
        return vm.parseJsonAddress(_sequenceJson, _getSequenceKey(name_, key_));
    }

    /// @notice Obtains an bool value from the given key in the deployment sequence
    /// @dev    This will revert if the key does not exist
    function _getSequenceBool(
        string memory name_,
        string memory key_
    ) internal view returns (bool) {
        return vm.parseJsonBool(_sequenceJson, _getSequenceKey(name_, key_));
    }
}
