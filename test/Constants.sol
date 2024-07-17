/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants as TestConstantsCore} from "@axis-core-0.9.0-test/Constants.sol";

abstract contract TestConstants is TestConstantsCore {
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAAc420c3C2940c5012a35Aa13b043Ab771c4f1E7);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAACFa2390F4ae6ACDc5a4a315A7d320E10E901f2);
    address internal constant _GUNI_FACTORY = address(0xAA50ce2b1C15321A2817D3c04F38Fd697B15E83b);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA58516d932C482469914260268EEA7611BF0eb4);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
