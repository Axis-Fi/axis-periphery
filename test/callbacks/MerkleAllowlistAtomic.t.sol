// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "@forge-std-1.9.1/Test.sol";
import {Callbacks} from "@axis-core-1.0.4/lib/Callbacks.sol";
import {Permit2User} from "@axis-core-1.0.4-test/lib/permit2/Permit2User.sol";

import {AtomicAuctionHouse} from "@axis-core-1.0.4/AtomicAuctionHouse.sol";

import {BaseCallback} from "@axis-core-1.0.4/bases/BaseCallback.sol";

import {MerkleAllowlist} from "../../src/callbacks/allowlists/MerkleAllowlist.sol";

import {WithSalts} from "../../script/salts/WithSalts.s.sol";
import {TestConstants} from "../Constants.sol";

contract MerkleAllowlistAtomicTest is Test, Permit2User, WithSalts, TestConstants {
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

    AtomicAuctionHouse internal _auctionHouse;
    MerkleAllowlist internal _allowlist;

    // Includes _BUYER, _BUYER_TWO but not _BUYER_THREE
    bytes32 internal constant _MERKLE_ROOT =
        0xc92348ba87c65979cc4f264810321a35efa64e795075908af2c507a22d4da472;
    bytes32[] internal _merkleProof;

    function setUp() public {
        // Create an AuctionHouse at a deterministic address, since it is used as input to callbacks
        AtomicAuctionHouse auctionHouse = new AtomicAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _auctionHouse = AtomicAuctionHouse(address(0x000000000000000000000000000000000000000A));
        vm.etch(address(_auctionHouse), address(auctionHouse).code);
        vm.store(address(_auctionHouse), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner
        vm.store(address(_auctionHouse), bytes32(uint256(6)), bytes32(abi.encode(1))); // Reentrancy
        vm.store(address(_auctionHouse), bytes32(uint256(10)), bytes32(abi.encode(_PROTOCOL))); // Protocol

        // Generate a salt for the contract
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });
        bytes32 salt = _generateSalt(
            "AtomicMerkleAllowlist",
            type(MerkleAllowlist).creationCode,
            abi.encode(address(_auctionHouse), permissions),
            "90"
        );

        vm.broadcast();
        _allowlist = new MerkleAllowlist{salt: salt}(address(_auctionHouse), permissions);

        _merkleProof.push(
            bytes32(0x16db2e4b9f8dc120de98f8491964203ba76de27b27b29c2d25f85a325cd37477)
        ); // Corresponds to _BUYER
    }

    modifier givenAtomicOnCreate() {
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

    function _onPurchase(uint96 lotId_, address buyer_, uint256 amount_) internal {
        vm.prank(address(_auctionHouse));
        _allowlist.onPurchase(lotId_, buyer_, amount_, 0, false, abi.encode(_merkleProof));
    }

    // onCreate
    // [X] when the allowlist parameters are in an incorrect format
    //  [X] it reverts
    // [X] if the caller is not the auction house
    //  [X] it reverts
    // [ ] if the merkle root is zero
    //  [ ] it sets the merkle root to zero
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

    function test_onCreate_alreadyRegistered_reverts() public givenAtomicOnCreate {
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

    function test_onCreate() public givenAtomicOnCreate {
        assertEq(_allowlist.lotIdRegistered(_lotId), true, "lotIdRegistered");
        assertEq(_allowlist.lotMerkleRoot(_lotId), _MERKLE_ROOT, "lotMerkleRoot");
    }

    // onPurchase
    // [X] if the caller is not the auction house
    //  [X] it reverts
    // [X] if the lot is not registered
    //  [X] it reverts
    // [ ] if the merkle root is zero
    //  [ ] it succeeds for any buyer
    // [X] if the buyer is not in the merkle tree
    //  [X] it reverts
    // [X] it succeeds

    function test_onPurchase_callerNotAuctionHouse_reverts() public givenAtomicOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _allowlist.onPurchase(_lotId, _BUYER, 1e18, 0, false, "");
    }

    function test_onPurchase_lotNotRegistered_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER, 1e18);
    }

    function test_onPurchase_buyerNotInMerkleTree_reverts() public givenAtomicOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER_THREE, 1e18);
    }

    function test_onPurchase(
        uint256 amount_
    ) public givenAtomicOnCreate {
        uint256 amount = bound(amount_, 1, 1e18);

        _onPurchase(_lotId, _BUYER, amount);
    }
}
