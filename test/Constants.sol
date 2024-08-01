/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants as TestConstantsCore} from "@axis-core-1.0.0-test/Constants.sol";

abstract contract TestConstants is TestConstantsCore {
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAAA62fF7f44f42344BE859f9CD5336809c160712);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAAa8B2Ad0f25a2D64686160b166f4bFa3BD62a8B);
    address internal constant _GUNI_FACTORY = address(0xAA148706ad079a0e8Df58b15292eB0412cB95A16);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAAf765c283ee0d5046284B662b3Baaec1a341Da1);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
