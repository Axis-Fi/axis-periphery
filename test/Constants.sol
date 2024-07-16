/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants} from "@axis-core-0.5.1-test/Constants.sol";

abstract contract TestConstantsPeriphery is TestConstants {
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAA9d46fFaA451Bc33E9A2722296656B7353255E9);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAAb39D61dfaDdac33747628FCcd808848dF67f54);
    address internal constant _GUNI_FACTORY = address(0xAA02c3B670819c4f85F04d6aCB7c560135E0Ff99);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA58516d932C482469914260268EEA7611BF0eb4);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
