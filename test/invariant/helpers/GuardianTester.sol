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

    function test_uni_v3() public {
        // baselineDTL_createLot(32834951442023372761398138891550170);
        // uniswapV2DTL_createLot(0,0,0,0);
        // baselineDTL_onSettle(0,0,0,0);
        // uniswapV2DTL_onSettle(0,0,0,0);
        // V2PoolHandler_swapToken0(24989087196341648061875939510755979066808,0);
        uniswapV3DTL_createLot(0,0,0,0);
        uniswapV3DTL_onCurate(0,0);
        uniswapV3DTL_onSettle(0,813287864469051073156,0,1005841494018651);
    }

    function test_baseline() public {
        uniswapV3DTL_createLot(437216507706592282876171117618922826437786610427871130838586195282963363,0,0,0);
        uniswapV3DTL_onSettle(636005900715977586173874473073298288870076909992124878864819,416450195249299281987,12825,19237704000);
        baselineDTL_createLot(34333282399156995958520823203444417106154321905272367517010186682772919);
        baselineDTL_onSettle(35823517419589735724585236993570690661427686147832812,547625172962746778936920119754048998529185575659961730593116,413846032223724352952166507982050954163269860227480398133,2378700954196402680978671333632440717118146550494);
    }
}
