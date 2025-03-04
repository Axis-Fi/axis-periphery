/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants as TestConstantsCore} from "@axis-core-1.0.4-test/Constants.sol";

abstract contract TestConstants is TestConstantsCore {
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAAB5b268B35f9e63c0D88EEfacC89785cC3077d4);
    // address internal constant _BASELINE_KERNEL = address(0xBB);
    // address internal constant _BASELINE_QUOTE_TOKEN =
    //     address(0xAABA4a4ef5c3C62a3F40e61BC675331662dB4D96);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    address internal constant _SELLER = address(0x2);
}
