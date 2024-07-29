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

    // Cleopatra addresses on Mantle
    address internal constant _CLEOPATRA_V1_FACTORY =
        address(0xAAA16c016BF556fcD620328f0759252E29b1AB57);
    address internal constant _CLEOPATRA_V1_ROUTER =
        address(0xAAA45c8F5ef92a000a121d102F4e89278a711Faa);
    address internal constant _CLEOPATRA_V2_FACTORY =
        address(0xAAA32926fcE6bE95ea2c51cB4Fcb60836D320C42);
    address internal constant _CLEOPATRA_V2_POSITION_MANAGER =
        address(0xAAA78E8C4241990B4ce159E105dA08129345946A);
}
