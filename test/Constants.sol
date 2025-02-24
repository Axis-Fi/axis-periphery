/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants as TestConstantsCore} from "@axis-core-1.0.4-test/Constants.sol";

abstract contract TestConstants is TestConstantsCore {
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAA063dB6d010722f4d29c000a8832f101b944570);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAA3023F92819f02180b25795a5797f69F3627Cb7);
    address internal constant _GUNI_FACTORY = address(0xAA19F2E4084fd3e49C198e616e181B82332000D5);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAABA4a4ef5c3C62a3F40e61BC675331662dB4D96);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    address internal constant _SELLER = address(0x2);
}
