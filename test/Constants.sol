/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants as TestConstantsCore} from "@axis-core-0.5.1-test/Constants.sol";

abstract contract TestConstants is TestConstantsCore {
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAA35004f2C3BaD6491B1Ee16d4a9E71b6b55B0Bf);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAA2C217496E84aa14C91E8A1Afd9087105675442);
    address internal constant _GUNI_FACTORY = address(0xAA27e6e5A26443183584a9c426aEC6Fdf83453C9);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA38266E47057628A7aC7943Ba0370A341F477f4);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
