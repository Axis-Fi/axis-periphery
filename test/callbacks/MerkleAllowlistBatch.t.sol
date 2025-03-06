// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "@forge-std-1.9.1/Test.sol";
import {Callbacks} from "@axis-core-1.0.4/lib/Callbacks.sol";
import {Permit2User} from "@axis-core-1.0.4-test/lib/permit2/Permit2User.sol";

import {BatchAuctionHouse} from "@axis-core-1.0.4/BatchAuctionHouse.sol";

import {BaseCallback} from "@axis-core-1.0.4/bases/BaseCallback.sol";

import {MerkleAllowlist} from "../../src/callbacks/allowlists/MerkleAllowlist.sol";

import {WithSalts} from "../../script/salts/WithSalts.s.sol";
import {TestConstants} from "../Constants.sol";

contract MerkleAllowlistBatchTest is Test, Permit2User, WithSalts, TestConstants {
    using Callbacks for MerkleAllowlist;

    address internal constant _PROTOCOL = address(0x3);
    address internal constant _BUYER = address(0x4);
    address internal constant _BUYER_TWO = address(0x5);
    address internal constant _BASE_TOKEN = address(0x6);
    address internal constant _QUOTE_TOKEN = address(0x7);
    address internal constant _SELLER_TWO = address(0x8);
    address internal constant _BUYER_THREE = address(0x9);

    uint256 internal constant _LOT_CAPACITY = 10e18;

    uint96 internal _lotId = 1;

    BatchAuctionHouse internal _auctionHouse;
    MerkleAllowlist internal _allowlist;

    // Includes _BUYER, _BUYER_TWO but not _BUYER_THREE
    bytes32 internal constant _MERKLE_ROOT =
        0xc92348ba87c65979cc4f264810321a35efa64e795075908af2c507a22d4da472;
    bytes32[] internal _merkleProof;

    function setUp() public {
        // Create an AuctionHouse at a deterministic address, since it is used as input to callbacks
        BatchAuctionHouse auctionHouse = new BatchAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _auctionHouse = BatchAuctionHouse(address(0x000000000000000000000000000000000000000A));
        vm.etch(address(_auctionHouse), address(auctionHouse).code);
        vm.store(address(_auctionHouse), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner
        vm.store(address(_auctionHouse), bytes32(uint256(6)), bytes32(abi.encode(1))); // Reentrancy
        vm.store(address(_auctionHouse), bytes32(uint256(10)), bytes32(abi.encode(_PROTOCOL))); // Protocol

        // Get the salt
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });
        bytes32 salt = _generateSalt(
            "BatchMerkleAllowlist",
            type(MerkleAllowlist).creationCode,
            abi.encode(address(_auctionHouse), permissions),
            "88"
        );

        vm.broadcast();
        _allowlist = new MerkleAllowlist{salt: salt}(address(_auctionHouse), permissions);

        _merkleProof.push(
            bytes32(0x16db2e4b9f8dc120de98f8491964203ba76de27b27b29c2d25f85a325cd37477)
        ); // Corresponds to _BUYER
    }

    modifier givenBatchOnCreate() {
        vm.prank(address(_auctionHouse));
        _allowlist.onCreate(
            _lotId,
            _SELLER,
            _BASE_TOKEN,
            _QUOTE_TOKEN,
            _LOT_CAPACITY,
            false,
            abi.encode(_MERKLE_ROOT)
        );
        _;
    }

    modifier givenBatchOnCreateMerkleRootZero() {
        vm.prank(address(_auctionHouse));
        _allowlist.onCreate(
            _lotId, _SELLER, _BASE_TOKEN, _QUOTE_TOKEN, _LOT_CAPACITY, false, abi.encode(bytes32(0))
        );
        _;
    }

    function _onBid(uint96 lotId_, address buyer_, uint256 amount_) internal {
        vm.prank(address(_auctionHouse));
        _allowlist.onBid(lotId_, 1, buyer_, amount_, abi.encode(_merkleProof));
    }

    // onCreate
    // [X] when the allowlist parameters are in an incorrect format
    //  [X] it reverts
    // [X] if the caller is not the auction house
    //  [X] it reverts
    // [X] if the merkle root is zero
    //  [X] it sets the merkle root to zero
    // [X] if the seller is not the seller for the allowlist
    //  [X] it sets the merkle root
    // [X] if the lot is already registered
    //  [X] it reverts
    // [X] it sets the merkle root

    function test_onCreate_allowlistParametersIncorrectFormat_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(address(_auctionHouse));
        _allowlist.onCreate(
            _lotId,
            _SELLER,
            _BASE_TOKEN,
            _QUOTE_TOKEN,
            _LOT_CAPACITY,
            false,
            abi.encode(_MERKLE_ROOT, uint256(20))
        );
    }

    function test_onCreate_callerNotAuctionHouse_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _allowlist.onCreate(
            _lotId,
            _SELLER,
            _BASE_TOKEN,
            _QUOTE_TOKEN,
            _LOT_CAPACITY,
            false,
            abi.encode(_MERKLE_ROOT)
        );
    }

    function test_onCreate_sellerNotSeller() public {
        vm.prank(address(_auctionHouse));
        _allowlist.onCreate(
            _lotId,
            _SELLER_TWO,
            _BASE_TOKEN,
            _QUOTE_TOKEN,
            _LOT_CAPACITY,
            false,
            abi.encode(_MERKLE_ROOT)
        );

        assertEq(_allowlist.lotIdRegistered(_lotId), true, "lotIdRegistered");
        assertEq(_allowlist.lotMerkleRoot(_lotId), _MERKLE_ROOT, "lotMerkleRoot");
    }

    function test_onCreate_alreadyRegistered_reverts() public givenBatchOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(address(_auctionHouse));
        _allowlist.onCreate(
            _lotId,
            _SELLER,
            _BASE_TOKEN,
            _QUOTE_TOKEN,
            _LOT_CAPACITY,
            false,
            abi.encode(_MERKLE_ROOT)
        );
    }

    function test_onCreate_merkleRootZero() public {
        // Call function
        vm.prank(address(_auctionHouse));
        _allowlist.onCreate(
            _lotId, _SELLER, _BASE_TOKEN, _QUOTE_TOKEN, _LOT_CAPACITY, false, abi.encode(bytes32(0))
        );

        // Assert
        assertEq(_allowlist.lotIdRegistered(_lotId), true, "lotIdRegistered");
        assertEq(_allowlist.lotMerkleRoot(_lotId), bytes32(0), "lotMerkleRoot");
    }

    function test_onCreate() public givenBatchOnCreate {
        assertEq(_allowlist.lotIdRegistered(_lotId), true, "lotIdRegistered");
        assertEq(_allowlist.lotMerkleRoot(_lotId), _MERKLE_ROOT, "lotMerkleRoot");
    }

    // onBid
    // [X] if the caller is not the auction house
    //  [X] it reverts
    // [X] if the lot is not registered
    //  [X] it reverts
    // [X] if the merkle root is zero
    //  [X] it succeeds for any buyer
    // [X] if the buyer is not in the merkle tree
    //  [X] it reverts
    // [X] it succeeds

    function test_onBid_callerNotAuctionHouse_reverts() public givenBatchOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _allowlist.onBid(_lotId, 1, _BUYER, 1e18, "");
    }

    function test_onBid_lotNotRegistered_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onBid(_lotId, _BUYER, 1e18);
    }

    function test_onBid_buyerNotInMerkleTree_reverts() public givenBatchOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onBid(_lotId, _BUYER_THREE, 1e18);
    }

    function test_onBid_merkleRootZero(
        address buyer_
    ) public givenBatchOnCreateMerkleRootZero {
        vm.assume(buyer_ != _BUYER && buyer_ != _BUYER_TWO);

        // Call function
        vm.prank(address(_auctionHouse));
        _allowlist.onBid(_lotId, 1, buyer_, 1e18, "");
    }

    function test_onBid(
        uint256 amount_
    ) public givenBatchOnCreate {
        uint256 amount = bound(amount_, 1, 1e18);

        _onBid(_lotId, _BUYER, amount);
    }
}
