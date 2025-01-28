// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MerkleProof} from "@openzeppelin-contracts-4.9.2/utils/cryptography/MerkleProof.sol";
import {Owned} from "@solmate-6.7.0/auth/Owned.sol";

import {UniswapV3DirectToLiquidity} from "./UniswapV3DTL.sol";
import {BaseDirectToLiquidity} from "./BaseDTL.sol";

/// @notice Allocated allowlist version of the Uniswap V3 Direct To Liquidity callback.
/// @notice This version allows for each address in the Merkle tree to have a per-address amount of quote tokens they can spend.
/// @dev    The merkle tree is expected to have both an address and an amount of quote tokens they can spend in each leaf.
contract UniswapV3DTLWithAllocatedAllowlist is UniswapV3DirectToLiquidity, Owned {
    // ========== ERRORS ========== //

    /// @notice Error message when the bid amount exceeds the limit assigned to a buyer
    error Callback_ExceedsLimit();

    /// @notice Error message when the callback state does not support the action
    error Callback_InvalidState();

    // ========== EVENTS ========== //

    /// @notice Emitted when the merkle root is set
    event MerkleRootSet(uint96 lotId, bytes32 merkleRoot);

    // ========== STATE VARIABLES ========== //

    /// @notice The root of the merkle tree that represents the allowlist
    /// @dev    The merkle tree should adhere to the format specified in the OpenZeppelin MerkleProof library at https://github.com/OpenZeppelin/merkle-tree
    ///         In particular, leaf values (such as `(address)` or `(address,uint256)`) should be double-hashed.
    mapping(uint96 => bytes32) public lotMerkleRoot;

    /// @notice Tracks the cumulative amount spent by a buyer
    mapping(uint96 => mapping(address => uint256)) public lotBuyerSpent;

    // ========== CONSTRUCTOR ========== //

    // PERMISSIONS
    // onCreate: true
    // onCancel: true
    // onCurate: true
    // onPurchase: false
    // onBid: true
    // onSettle: true
    // receiveQuoteTokens: true
    // sendBaseTokens: true
    // Contract prefix should be: 11101111 = 0xEF

    constructor(
        address auctionHouse_,
        address uniV3Factory_,
        address gUniFactory_,
        address owner_
    ) UniswapV3DirectToLiquidity(auctionHouse_, uniV3Factory_, gUniFactory_) Owned(owner_) {}

    // ========== CALLBACKS ========== //

    /// @inheritdoc BaseDirectToLiquidity
    function __onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual override {
        // Validate the UniswapV3 parameters
        super.__onCreate(
            lotId_, seller_, baseToken_, quoteToken_, capacity_, prefund_, callbackData_
        );

        // Check that the parameters are of the correct length
        if (callbackData_.length != 32) {
            revert Callback_InvalidParams();
        }

        // Decode the merkle root from the callback data
        bytes32 merkleRootParams = abi.decode(callbackData_, (bytes32));

        // Set the merkle root and buyer limit
        lotMerkleRoot[lotId_] = merkleRootParams;
        emit MerkleRootSet(lotId_, merkleRootParams);
    }

    /// @inheritdoc BaseDirectToLiquidity
    ///
    /// @param      callbackData_   abi-encoded data: (bytes32[], uint256) representing the merkle proof and allocated amount
    function _onBid(
        uint96 lotId_,
        uint64 bidId_,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal pure override {
        // Validate that the buyer is allowed to participate
        uint256 allocatedAmount = _canParticipate(lotId_, buyer_, callbackData_);

        // Validate that the buyer can buy the amount
        _canBuy(lotId_, buyer_, amount_, allocatedAmount);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @dev The buyer must provide the proof and their total allocated amount in the callback data for this to succeed.
    function _canParticipate(
        uint96 lotId_,
        address buyer_,
        bytes calldata callbackData_
    ) internal view returns (uint256) {
        // Decode the merkle proof from the callback data
        (bytes32[] memory proof, uint256 allocatedAmount) =
            abi.decode(callbackData_, (bytes32[], uint256));

        // Get the leaf for the buyer
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(buyer_, allocatedAmount))));

        // Validate the merkle proof
        if (!MerkleProof.verify(proof, lotMerkleRoot[lotId_], leaf)) {
            revert Callback_NotAuthorized();
        }

        // Return the allocated amount for the buyer
        return allocatedAmount;
    }

    function _canBuy(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        uint256 allocatedAmount_
    ) internal {
        // Check if the buyer has already spent their limit
        if (lotBuyerSpent[lotId_][buyer_] + amount_ > allocatedAmount_) {
            revert Callback_ExceedsLimit();
        }

        // Update the buyer spent amount
        lotBuyerSpent[lotId_][buyer_] += amount_;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Sets the merkle root for the allowlist
    ///         This function can be called by the owner to update the merkle root after `onCreate()`.
    /// @dev    This function performs the following:
    ///         - Performs validation
    ///         - Sets the merkle root
    ///         - Emits a MerkleRootSet event
    ///
    ///         This function reverts if:
    ///         - The caller is not the owner
    ///         - The auction has not been registered
    ///         - The auction has been completed
    ///
    /// @param  merkleRoot_ The new merkle root
    function setMerkleRoot(uint96 lotId_, bytes32 merkleRoot_) external onlyOwner {
        // Revert if onCreate has not been called
        if (lotId_ == type(uint96).max) {
            revert Callback_InvalidState();
        }

        // Revert if the auction has been completed already
        if (!lotConfiguration[lotId_].active) {
            revert Callback_AlreadyComplete();
        }

        lotMerkleRoot[lotId_] = merkleRoot_;

        emit MerkleRootSet(lotId_, merkleRoot_);
    }
}
