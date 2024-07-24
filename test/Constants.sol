/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants as TestConstantsCore} from "@axis-core-1.0.0-test/Constants.sol";

abstract contract TestConstants is TestConstantsCore {
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAAFe095EbE5E7e9038E218e248F9Fb97F42D8307);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAA3eFeA0D4a1e2c3503a7088AcF6d1aEB0f37dc1);
    address internal constant _GUNI_FACTORY = address(0xAA9Fa39aa52e2D97Ff1C2C71249EB24e02617F1e);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA925e09442671E980F5d26827193Ea43A7576EC);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
