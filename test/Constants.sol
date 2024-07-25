/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants as TestConstantsCore} from "@axis-core-1.0.0-test/Constants.sol";

abstract contract TestConstants is TestConstantsCore {
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAAf663c9E2FE1EBE2a5930026d1ffEC4475b9608);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAAd7024D1Fa43a88d975e441E18Dd26E5973e53A);
    address internal constant _GUNI_FACTORY = address(0xAA7Fd572432bC7C7Ee41E81d24A98FfEee858a35);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA57CB5d789F3E3343eE786d94495507A94b7Fc7);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
