// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title  IMerkleAllowlist
/// @notice Defines the interface for the MerkleAllowlist contract, which provides a merkle tree-based allowlist for buyers to participate in an auction.
interface IMerkleAllowlist {
    // ========== EVENTS ========== //

    /// @notice Emitted when the merkle root is set
    event MerkleRootSet(uint96 lotId, bytes32 merkleRoot);

    // ========== FUNCTIONS ========== //

    /// @notice Gets the merkle root for the allowlist
    ///
    /// @param  lotId_      The ID of the lot
    /// @return merkleRoot  The merkle root for the allowlist
    function lotMerkleRoot(uint96 lotId_) external view returns (bytes32 merkleRoot);

    /// @notice Sets the merkle root for the allowlist
    ///         This function can be called by the lot's seller to update the merkle root after `onCreate()`.
    /// @dev    This function performs the following:
    ///         - Performs validation
    ///         - Sets the merkle root
    ///         - Emits a MerkleRootSet event
    ///
    /// @param  lotId_      The ID of the lot
    /// @param  merkleRoot_ The new merkle root
    function setMerkleRoot(uint96 lotId_, bytes32 merkleRoot_) external;
}
