// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {UniswapV2DTLHandler} from "./handlers/UniswapV2DTLHandler.sol";
import {UniswapV3DTLHandler} from "./handlers/UniswapV3DTLHandler.sol";
import {BaselineDTLHandler} from "./handlers/BaselineDTLHandler.sol";
import {V2PoolHandler} from "./handlers/V2PoolHandler.sol";
import {V3PoolHandler} from "./handlers/V3PoolHandler.sol";
import {BaselinePoolHandler} from "./handlers/BaselinePoolHandler.sol";

// forgefmt: disable-start
/**************************************************************************************************************/
/*** AxisInvariant is the highest level contract that contains all setup, handlers, and invariants for      ***/
/*** the Axis Fuzz Suite.                                                                                   ***/
/**************************************************************************************************************/
// forgefmt: disable-end
contract AxisInvariant is
    UniswapV2DTLHandler,
    UniswapV3DTLHandler,
    BaselineDTLHandler,
    V2PoolHandler,
    V3PoolHandler,
    BaselinePoolHandler
{
    constructor() payable {
        setup();
    }
}
