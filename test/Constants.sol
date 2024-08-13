/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants as TestConstantsCore} from "@axis-core-1.0.0-test/Constants.sol";

abstract contract TestConstants is TestConstantsCore {
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAA94DEa063488d164535494E3Ed118901296C9A1);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAA4E5F0C1872440c0eD7FbA62048c063b3ac1d00);
    address internal constant _GUNI_FACTORY = address(0xAA287a271e8974956E8591F17879e21f760CEF7B);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA0d07fC9065B7910A9E50a8a8184eE2a0a6179e);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
