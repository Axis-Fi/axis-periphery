// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IUniswapV3DTLWithAllocatedAllowlist {
    // ========== ERRORS ========== //

    /// @notice Error message when the bid amount exceeds the limit assigned to a buyer
    error Callback_ExceedsLimit();

    /// @notice Error message when the callback state does not support the action
    error Callback_InvalidState();

    // ========== EVENTS ========== //

    /// @notice Emitted when the merkle root is set
    event MerkleRootSet(uint96 lotId, bytes32 merkleRoot);

    // ========== ADMIN ========== //

    /// @notice Sets the merkle root for the allowlist
    ///         This function can be called by the seller to update the merkle root after `onCreate()`.
    /// @dev    This function can only be called by the seller
    ///
    /// @param  lotId_ The lot ID
    /// @param  merkleRoot_ The merkle root
    function setMerkleRoot(uint96 lotId_, bytes32 merkleRoot_) external;
}
