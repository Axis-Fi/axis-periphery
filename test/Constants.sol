/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestConstants as TestConstantsCore} from "@axis-core-1.0.0-test/Constants.sol";

abstract contract TestConstants is TestConstantsCore {
    address internal constant _UNISWAP_V2_FACTORY =
        address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    address internal constant _UNISWAP_V2_ROUTER =
        address(0xAAcF36e66E48D0fb8f12381daC69Aa9FA1C69159);
    address internal constant _UNISWAP_V3_FACTORY =
        address(0xAAe4d0F0f763EC4777ae9419C6D83A566e884b77);
    address internal constant _GUNI_FACTORY = address(0xAA62AaF5Bf60f9b7E9bc0C257785b38d039b805e);
    address internal constant _BASELINE_KERNEL = address(0xBB);
    address internal constant _BASELINE_QUOTE_TOKEN =
        address(0xAA8fFfB79588c028237300E0B7F6F1923cca651C);
    address internal constant _CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
}
