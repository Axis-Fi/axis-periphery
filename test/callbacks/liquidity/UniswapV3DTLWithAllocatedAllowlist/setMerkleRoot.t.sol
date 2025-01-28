// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityWithAllocatedAllowlistTest} from
    "./UniswapV3DTLWithAllocatedAllowlistTest.sol";
import {UniswapV3DTLWithAllocatedAllowlist} from
    "src/callbacks/liquidity/UniswapV3DTLWithAllocatedAllowlist.sol";
import {BaseCallback} from "@axis-core-1.0.1/bases/BaseCallback.sol";
import {BaseDirectToLiquidity} from "src/callbacks/liquidity/BaseDTL.sol";

contract UniswapV3DTLWithAllocatedAllowlistSetMerkleRootTest is
    UniswapV3DirectToLiquidityWithAllocatedAllowlistTest
{
    event MerkleRootSet(uint96 lotId, bytes32 merkleRoot);

    // when the auction has not been registered
    //  [X] it reverts
    // when the caller is not the seller
    //  [X] it reverts
    // when the auction has been completed
    //  [ X] it reverts
    // [X] the merkle root is updated and an event is emitted

    function test_auctionNotRegistered_reverts() public givenCallbackIsCreated {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            UniswapV3DTLWithAllocatedAllowlist.Callback_InvalidState.selector
        );
        vm.expectRevert(err);

        // Call the callback
        vm.prank(_SELLER);
        _dtl.setMerkleRoot(_lotId, _MERKLE_ROOT);
    }

    function test_callerIsNotSeller_reverts() public givenCallbackIsCreated givenOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        // Call the callback
        vm.prank(address(_auctionHouse));
        _dtl.setMerkleRoot(_lotId, _MERKLE_ROOT);
    }

    function test_auctionCompleted_reverts() public givenCallbackIsCreated givenOnCreate {
        _performOnCancel();

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(BaseDirectToLiquidity.Callback_AlreadyComplete.selector);
        vm.expectRevert(err);

        // Call the callback
        vm.prank(_SELLER);
        _dtl.setMerkleRoot(_lotId, _MERKLE_ROOT);
    }

    function test_success() public givenCallbackIsCreated givenOnCreate {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit MerkleRootSet(_lotId, _MERKLE_ROOT);

        // Call the callback
        vm.prank(_SELLER);
        _dtl.setMerkleRoot(_lotId, _MERKLE_ROOT);

        // Assert the merkle root is updated
        assertEq(_dtl.lotMerkleRoot(_lotId), _MERKLE_ROOT);
    }
}
