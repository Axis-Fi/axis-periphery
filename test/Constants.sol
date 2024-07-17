/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants as TestConstantsCore} from "@axis-core-0.9.0-test/Constants.sol";

abstract contract TestConstants is TestConstantsCore {
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAAC26e617eEeDce14ca384b3EDAce4dC688cE08A);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAAa6edD3Ef4354C30415687584288A518B7FfBA8);
    address internal constant _GUNI_FACTORY = address(0xAAE2A775Ac2F1F1D423262Ed7b537d4f82ED255b);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA58516d932C482469914260268EEA7611BF0eb4);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
