/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants as TestConstantsCore} from "@axis-core-1.0.0-test/Constants.sol";

abstract contract TestConstants is TestConstantsCore {
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAAe4679eF7310cf51b402Fb4F94F44ead5ECc4dE);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAA488cE61A9bE80659e2C6Fd5A9E7BeFD58378E8);
    address internal constant _GUNI_FACTORY = address(0xAA874586eAaF809890C6d2F00862225b6Bb3577f);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA22883d39ea4e42f7033e3e931aA476DEe30b73);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
