// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {stdJson} from "@forge-std-1.9.1/StdJson.sol";

abstract contract WithEnvironment is Script {
    using stdJson for string;

    string public chain;
    string public env;
    string public envAxisCore;

    function _loadEnv(
        string calldata chain_
    ) internal {
        chain = chain_;
        console2.log("Using chain:", chain_);

        // Load environment file
        env = vm.readFile("./script/env.json");
        envAxisCore = vm.readFile("dependencies/axis-core-1.0.4/script/env.json");
    }

    /// @notice Get address from environment file
    /// @dev    First checks in the current chain's environment file, then in axis-core's environment file
    ///
    /// @param  key_    The key to look up in the environment file
    /// @return address The address from the environment file, or the zero address
    function _envAddress(
        string memory key_
    ) internal view returns (address) {
        string memory fullKey = string.concat(".current.", chain, ".", key_);
        address addr;
        bool keyExists = vm.keyExists(env, fullKey);

        if (keyExists) {
            addr = env.readAddress(fullKey);
            console2.log("    %s: %s (from env.json)", key_, addr);
        } else {
            keyExists = vm.keyExists(envAxisCore, fullKey);

            if (keyExists) {
                addr = envAxisCore.readAddress(fullKey);
                console2.log("    %s: %s (from axis-core/env.json)", key_, addr);
            } else {
                console2.log("    %s: *** NOT FOUND ***", key_);
            }
        }

        return addr;
    }

    /// @notice Get a non-zero address from environment file
    /// @dev    First checks in the current chain's environment file, then in axis-core's environment file
    ///
    ///         Reverts if the key is not found
    ///
    /// @param  key_    The key to look up in the environment file
    /// @return address The address from the environment file
    function _envAddressNotZero(
        string memory key_
    ) internal view returns (address) {
        address addr = _envAddress(key_);
        require(
            addr != address(0), string.concat("WithEnvironment: key '", key_, "' has zero address")
        );

        return addr;
    }
}
