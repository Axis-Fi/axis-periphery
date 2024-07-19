/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {WithEnvironment} from "../../deploy/WithEnvironment.s.sol";
import {WithSalts} from "../WithSalts.s.sol";

import {BaselineAxisLaunch} from
    "../../../src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {BALwithAllocatedAllowlist} from
    "../../../src/callbacks/liquidity/BaselineV2/BALwithAllocatedAllowlist.sol";
import {BALwithAllowlist} from "../../../src/callbacks/liquidity/BaselineV2/BALwithAllowlist.sol";
import {BALwithCappedAllowlist} from
    "../../../src/callbacks/liquidity/BaselineV2/BALwithCappedAllowlist.sol";
import {BALwithTokenAllowlist} from
    "../../../src/callbacks/liquidity/BaselineV2/BALwithTokenAllowlist.sol";

contract BaselineSalts is Script, WithEnvironment, WithSalts {
    string internal constant _ADDRESS_PREFIX = "EF";

    address internal _envBatchAuctionHouse;

    function _isDefaultDeploymentKey(string memory str) internal pure returns (bool) {
        // If the string is "DEFAULT", it's the default deployment key
        return keccak256(abi.encode(str)) == keccak256(abi.encode("DEFAULT"));
    }

    function _setUp(string calldata chain_) internal {
        _loadEnv(chain_);
        _createBytecodeDirectory();

        // Cache auction houses
        _envBatchAuctionHouse = _envAddressNotZero("deployments.BatchAuctionHouse");
    }

    function generate(
        string calldata chain_,
        string calldata variant_,
        string calldata baselineKernel_,
        string calldata baselineOwner_,
        string calldata reserveToken_,
        string calldata deploymentKeySuffix_
    ) public {
        _setUp(chain_);
        string memory deploymentKeySuffix =
            _isDefaultDeploymentKey(deploymentKeySuffix_) ? "" : deploymentKeySuffix_;
        bytes memory contractArgs_ = abi.encode(
            _envBatchAuctionHouse,
            vm.parseAddress(baselineKernel_),
            vm.parseAddress(reserveToken_),
            vm.parseAddress(baselineOwner_)
        );

        if (
            keccak256(abi.encodePacked(variant_))
                == keccak256(abi.encodePacked("BaselineAxisLaunch"))
        ) {
            _generateBaselineAxisLaunch(contractArgs_, deploymentKeySuffix);
        } else if (
            keccak256(abi.encodePacked(variant_))
                == keccak256(abi.encodePacked("BaselineAllocatedAllowlist"))
        ) {
            _generateBaselineAllocatedAllowlist(contractArgs_, deploymentKeySuffix);
        } else if (
            keccak256(abi.encodePacked(variant_))
                == keccak256(abi.encodePacked("BaselineAllowlist"))
        ) {
            _generateBaselineAllowlist(contractArgs_, deploymentKeySuffix);
        } else if (
            keccak256(abi.encodePacked(variant_))
                == keccak256(abi.encodePacked("BaselineCappedAllowlist"))
        ) {
            _generateBaselineCappedAllowlist(contractArgs_, deploymentKeySuffix);
        } else if (
            keccak256(abi.encodePacked(variant_))
                == keccak256(abi.encodePacked("BaselineTokenAllowlist"))
        ) {
            _generateBaselineTokenAllowlist(contractArgs_, deploymentKeySuffix);
        } else {
            revert(
                "Invalid variant: BaselineAxisLaunch or BaselineAllocatedAllowlist or BaselineAllowlist or BaselineCappedAllowlist or BaselineTokenAllowlist"
            );
        }
    }

    function _generateBaselineAxisLaunch(
        bytes memory contractArgs_,
        string memory deploymentKeySuffix_
    ) internal {
        bytes memory contractCode = type(BaselineAxisLaunch).creationCode;
        string memory deploymentKey = string.concat("BaselineAxisLaunch", deploymentKeySuffix_);

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey, contractCode, contractArgs_);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey, bytecodeHash);
    }

    function _generateBaselineAllocatedAllowlist(
        bytes memory contractArgs_,
        string memory deploymentKeySuffix_
    ) internal {
        bytes memory contractCode = type(BALwithAllocatedAllowlist).creationCode;
        string memory deploymentKey =
            string.concat("BaselineAllocatedAllowlist", deploymentKeySuffix_);

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey, contractCode, contractArgs_);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey, bytecodeHash);
    }

    function _generateBaselineAllowlist(
        bytes memory contractArgs_,
        string memory deploymentKeySuffix_
    ) internal {
        bytes memory contractCode = type(BALwithAllowlist).creationCode;
        string memory deploymentKey = string.concat("BaselineAllowlist", deploymentKeySuffix_);

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey, contractCode, contractArgs_);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey, bytecodeHash);
    }

    function _generateBaselineCappedAllowlist(
        bytes memory contractArgs_,
        string memory deploymentKeySuffix_
    ) internal {
        bytes memory contractCode = type(BALwithCappedAllowlist).creationCode;
        string memory deploymentKey = string.concat("BaselineCappedAllowlist", deploymentKeySuffix_);

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey, contractCode, contractArgs_);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey, bytecodeHash);
    }

    function _generateBaselineTokenAllowlist(
        bytes memory contractArgs_,
        string memory deploymentKeySuffix_
    ) internal {
        bytes memory contractCode = type(BALwithTokenAllowlist).creationCode;
        string memory deploymentKey = string.concat("BaselineTokenAllowlist", deploymentKeySuffix_);

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode(deploymentKey, contractCode, contractArgs_);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, deploymentKey, bytecodeHash);
    }
}
