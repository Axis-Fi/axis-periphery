// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "@forge-std-1.9.1/Test.sol";
import {console2} from "@forge-std-1.9.1/console2.sol";
import {UniswapV2DTLHandler} from "../handlers/UniswapV2DTLHandler.sol";
import {UniswapV3DTLHandler} from "../handlers/UniswapV3DTLHandler.sol";
import {V2PoolHandler} from "../handlers/V2PoolHandler.sol";
import {V3PoolHandler} from "../handlers/V3PoolHandler.sol";

contract GuardianTester is
    UniswapV2DTLHandler,
    UniswapV3DTLHandler,
    V2PoolHandler,
    V3PoolHandler
{
    function setUp() public {
        setup();
    }

    function test_replay() public {}

    function test_AX_52() public {
        V2PoolHandler_donate(1, 0);
        uniswapV2DTL_createLot(0, 0, 0, 0);
        V2PoolHandler_sync();
        uniswapV2DTL_onSettle(0, 0, 0, 0);
    }

    function test_uni_v3() public {
        uniswapV3DTL_createLot(0, 0, 0, 0);
        uniswapV3DTL_onCurate(0, 0);
        uniswapV3DTL_onSettle(0, 813_287_864_469_051_073_156, 0, 1_005_841_494_018_651);
    }

    function test_baseline() public {
        uniswapV3DTL_createLot(
            437_216_507_706_592_282_876_171_117_618_922_826_437_786_610_427_871_130_838_586_195_282_963_363,
            0,
            0,
            0
        );
        uniswapV3DTL_onSettle(
            636_005_900_715_977_586_173_874_473_073_298_288_870_076_909_992_124_878_864_819,
            416_450_195_249_299_281_987,
            12_825,
            19_237_704_000
        );
    }
}
