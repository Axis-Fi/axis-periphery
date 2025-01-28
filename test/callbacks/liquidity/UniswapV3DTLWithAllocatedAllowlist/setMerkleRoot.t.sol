// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityWithAllocatedAllowlistTest} from
    "./UniswapV3DTLWithAllocatedAllowlistTest.sol";

contract UniswapV3DTLWithAllocatedAllowlistSetMerkleRootTest is
    UniswapV3DirectToLiquidityWithAllocatedAllowlistTest
{
// when the auction has not been registered
//  [ ] it reverts
// when the caller is not the seller
//  [ ] it reverts
// [ ] when the auction has been completed
//  [ ] it reverts
// [ ] the merkle root is updated and an event is emitted
}
