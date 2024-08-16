// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./String.sol";

/// @author Based on Crytic PropertiesHelper (https://github.com/crytic/properties/blob/main/contracts/util/PropertiesHelper.sol)
abstract contract Assertions {
    event AssertFail(string);
    event assertEqualFail(string);
    event AssertNeqFail(string);
    event AssertGteFail(string);
    event AssertGtFail(string);
    event AssertLteFail(string);
    event AssertLtFail(string);
    event Message(string a);
    event MessageUint(string a, uint256 b);

    function t(bool b, string memory reason) internal {
        if (!b) {
            emit AssertFail(reason);
            assert(false);
        }
    }

    /// @notice asserts that a is equal to b. Violations are logged using reason.
    function equal(uint256 a, uint256 b, string memory reason) internal {
        if (a != b) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, "!=", reason);
            emit assertEqualFail(assertMsg);
            assert(false);
        }
    }

    /// @notice int256 version of equal
    function equal(int256 a, int256 b, string memory reason) internal {
        if (a != b) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, "!=", reason);
            emit assertEqualFail(assertMsg);
            assert(false);
        }
    }

    /// @notice bool version of equal
    function equal(bool a, bool b, string memory reason) internal {
        if (a != b) {
            string memory aStr = a ? "true" : "false";
            string memory bStr = b ? "true" : "false";
            string memory assertMsg = createAssertFailMessage(aStr, bStr, "!=", reason);
            emit assertEqualFail(assertMsg);
            assert(false);
        }
    }

    /// @notice address version of equal
    function equal(address a, address b, string memory reason) internal {
        if (a != b) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, "!=", reason);
            emit assertEqualFail(assertMsg);
            assert(false);
        }
    }

    /// @notice bytes4 version of equal
    function equal(bytes4 a, bytes4 b, string memory reason) internal {
        if (a != b) {
            bytes memory aBytes = abi.encodePacked(a);
            bytes memory bBytes = abi.encodePacked(b);
            string memory aStr = String.toHexString(aBytes);
            string memory bStr = String.toHexString(bBytes);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, "!=", reason);
            emit assertEqualFail(assertMsg);
            assert(false);
        }
    }

    /// @notice asserts that a is not equal to b. Violations are logged using reason.
    function neq(uint256 a, uint256 b, string memory reason) internal {
        if (a == b) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, "==", reason);
            emit AssertNeqFail(assertMsg);
            assert(false);
        }
    }

    /// @notice int256 version of neq
    function neq(int256 a, int256 b, string memory reason) internal {
        if (a == b) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, "==", reason);
            emit AssertNeqFail(assertMsg);
            assert(false);
        }
    }

    /// @notice asserts that a is greater than or equal to b. Violations are logged using reason.
    function gte(uint256 a, uint256 b, string memory reason) internal {
        if (!(a >= b)) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, "<", reason);
            emit AssertGteFail(assertMsg);
            assert(false);
        }
    }

    /// @notice int256 version of gte
    function gte(int256 a, int256 b, string memory reason) internal {
        if (!(a >= b)) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, "<", reason);
            emit AssertGteFail(assertMsg);
            assert(false);
        }
    }

    /// @notice asserts that a is greater than b. Violations are logged using reason.
    function gt(uint256 a, uint256 b, string memory reason) internal {
        if (!(a > b)) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, "<=", reason);
            emit AssertGtFail(assertMsg);
            assert(false);
        }
    }

    /// @notice int256 version of gt
    function gt(int256 a, int256 b, string memory reason) internal {
        if (!(a > b)) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, "<=", reason);
            emit AssertGtFail(assertMsg);
            assert(false);
        }
    }

    /// @notice asserts that a is less than or equal to b. Violations are logged using reason.
    function lte(uint256 a, uint256 b, string memory reason) internal {
        if (!(a <= b)) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, ">", reason);
            emit AssertLteFail(assertMsg);
            assert(false);
        }
    }

    /// @notice int256 version of lte
    function lte(int256 a, int256 b, string memory reason) internal {
        if (!(a <= b)) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, ">", reason);
            emit AssertLteFail(assertMsg);
            assert(false);
        }
    }

    /// @notice asserts that a is less than b. Violations are logged using reason.
    function lt(uint256 a, uint256 b, string memory reason) internal {
        if (!(a < b)) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, ">=", reason);
            emit AssertLtFail(assertMsg);
            assert(false);
        }
    }

    /// @notice int256 version of lt
    function lt(int256 a, int256 b, string memory reason) internal {
        if (!(a < b)) {
            string memory aStr = String.toString(a);
            string memory bStr = String.toString(b);
            string memory assertMsg = createAssertFailMessage(aStr, bStr, ">=", reason);
            emit AssertLtFail(assertMsg);
            assert(false);
        }
    }

    function assertApproxEq(
        uint256 a,
        uint256 b,
        uint256 maxDelta,
        string memory reason
    ) internal {
        if (!(a == b)) {
            uint256 dt = b > a ? b - a : a - b;
            if (dt > maxDelta) {
                emit Message("Error: a =~ b not satisfied [uint]");
                emit MessageUint("   Value a", a);
                emit MessageUint("   Value b", b);
                emit MessageUint(" Max Delta", maxDelta);
                emit MessageUint("     Delta", dt);
                t(false, reason);
            }
        } else {
            t(true, "a == b");
        }
    }

    function assertRevertReasonNotEqual(bytes memory returnData, string memory reason) internal {
        bool isEqual = String.isRevertReasonEqual(returnData, reason);
        t(!isEqual, reason);
    }

    function assertRevertReasonEqual(bytes memory returnData, string memory reason) internal {
        bool isEqual = String.isRevertReasonEqual(returnData, reason);
        t(isEqual, reason);
    }

    function assertRevertReasonEqual(
        bytes memory returnData,
        string memory reason1,
        string memory reason2
    ) internal {
        bool isEqual = String.isRevertReasonEqual(returnData, reason1)
            || String.isRevertReasonEqual(returnData, reason2);
        string memory assertMsg = string(abi.encodePacked(reason1, " OR ", reason2));
        t(isEqual, assertMsg);
    }

    function assertRevertReasonEqual(
        bytes memory returnData,
        string memory reason1,
        string memory reason2,
        string memory reason3
    ) internal {
        bool isEqual = String.isRevertReasonEqual(returnData, reason1)
            || String.isRevertReasonEqual(returnData, reason2)
            || String.isRevertReasonEqual(returnData, reason3);
        string memory assertMsg =
            string(abi.encodePacked(reason1, " OR ", reason2, " OR ", reason3));
        t(isEqual, assertMsg);
    }

    function assertRevertReasonEqual(
        bytes memory returnData,
        string memory reason1,
        string memory reason2,
        string memory reason3,
        string memory reason4
    ) internal {
        bool isEqual = String.isRevertReasonEqual(returnData, reason1)
            || String.isRevertReasonEqual(returnData, reason2)
            || String.isRevertReasonEqual(returnData, reason3)
            || String.isRevertReasonEqual(returnData, reason4);
        string memory assertMsg =
            string(abi.encodePacked(reason1, " OR ", reason2, " OR ", reason3, " OR ", reason4));
        t(isEqual, assertMsg);
    }

    function errAllow(
        bytes4 errorSelector,
        bytes4[] memory allowedErrors,
        string memory message
    ) internal {
        bool allowed = false;
        for (uint256 i = 0; i < allowedErrors.length; i++) {
            if (errorSelector == allowedErrors[i]) {
                allowed = true;
                break;
            }
        }
        t(allowed, message);
    }

    function errsAllow(
        bytes4 errorSelector,
        bytes4[] memory allowedErrors,
        string[] memory messages
    ) internal {
        bool allowed = false;
        uint256 passIndex = 0;
        for (uint256 i = 0; i < allowedErrors.length; i++) {
            if (errorSelector == allowedErrors[i]) {
                allowed = true;
                passIndex = i;
                break;
            }
        }
        t(allowed, messages[passIndex]);
    }

    function createAssertFailMessage(
        string memory aStr,
        string memory bStr,
        string memory operator,
        string memory reason
    ) internal pure returns (string memory) {
        return string(abi.encodePacked("Invalid: ", aStr, operator, bStr, ", reason: ", reason));
    }
}
