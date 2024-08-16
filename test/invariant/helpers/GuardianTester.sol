// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "@forge-std-1.9.1/Test.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";
import {UniswapV2DTLHandler} from "../handlers/UniswapV2DTLHandler.sol";
import {UniswapV3DTLHandler} from "../handlers/UniswapV3DTLHandler.sol";
import {BaselineDTLHandler} from "../handlers/BaselineDTLHandler.sol";
import {V2PoolHandler} from "../handlers/V2PoolHandler.sol";
import {V3PoolHandler} from "../handlers/V3PoolHandler.sol";
import {BaselinePoolHandler} from "../handlers/BaselinePoolHandler.sol";

contract GuardianTester is
    UniswapV2DTLHandler,
    UniswapV3DTLHandler,
    BaselineDTLHandler,
    V2PoolHandler,
    V3PoolHandler,
    BaselinePoolHandler
{
    function setUp() public {
        setup();
    }

    function test_replay() public {
        baselineDTL_createLot(5308999150487892971068021905251623733433234150124587658902863958762);
    }

    function test_AX_52() public {
        V2PoolHandler_donate(112886133825346617639844941255172917887440337226870667044252754906299314805,539737169161019179227400595);
        V2PoolHandler_sync();
        uniswapV2DTL_createLot(530731744443093305528217931931588750699732268462698379454214214516981,15,34391715174,2911279);
        uniswapV2DTL_onSettle(74242834330818981373611912035815288202893171282512133578955136337658302516,0,684922578086812823641066,2106608095978665836350501);
    }
}
