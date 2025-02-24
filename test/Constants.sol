/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants as TestConstantsCore} from "@axis-core-1.0.4-test/Constants.sol";

abstract contract TestConstants is TestConstantsCore {
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAA90Afc992900e395D77cBb02D22FF5ef04bC9b9);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAA6e0bD8aA20a2Fb885f378d8d98088aFEf56faD);
    address internal constant _GUNI_FACTORY = address(0xAAF4DB8Fc32Cb0Fee88cAA609466608C10e01940);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA5962E03F408601D4044cb90592f9075772641F);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    address internal constant _SELLER = address(0x2);
}
