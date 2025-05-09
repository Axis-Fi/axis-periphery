// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "@forge-std-1.9.1/Test.sol";
import {Callbacks} from "@axis-core-1.0.4/lib/Callbacks.sol";
import {Permit2User} from "@axis-core-1.0.4-test/lib/permit2/Permit2User.sol";

import {IAuctionHouse} from "@axis-core-1.0.4/interfaces/IAuctionHouse.sol";
import {AtomicAuctionHouse} from "@axis-core-1.0.4/AtomicAuctionHouse.sol";

import {BaseCallback} from "@axis-core-1.0.4/bases/BaseCallback.sol";

import {AllocatedMerkleAllowlist} from "../../src/callbacks/allowlists/AllocatedMerkleAllowlist.sol";

import {toVeecode} from "@axis-core-1.0.4/modules/Keycode.sol";
import {WithSalts} from "../../script/salts/WithSalts.s.sol";
import {TestConstants} from "../Constants.sol";

contract AllocatedMerkleAllowlistAtomicTest is Test, Permit2User, WithSalts, TestConstants {
    using Callbacks for AllocatedMerkleAllowlist;

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
    AllocatedMerkleAllowlist internal _allowlist;

    // _BUYER: 5e18
    // 0x20: 0
    bytes32 internal constant _MERKLE_ROOT =
        0x0fdc3942d9af344db31ff2e80c06bc4e558dc967ca5b4d421d741870f5ea40df;
    bytes32[] internal _merkleProof;
    uint256 internal constant _BUYER_ALLOCATED_AMOUNT = 5e18;

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
            "AtomicAllocatedMerkleAllowlist",
            type(AllocatedMerkleAllowlist).creationCode,
            abi.encode(address(_auctionHouse), permissions),
            "90"
        );

        vm.broadcast();
        _allowlist = new AllocatedMerkleAllowlist{salt: salt}(address(_auctionHouse), permissions);

        _merkleProof.push(
            bytes32(0x2eac7b0cadd960cd4457012a5e232aa3532d9365ba6df63c1b5a9c7846f77760)
        ); // Corresponds to _BUYER
    }

    function _mockLotRouting() internal {
        vm.mockCall(
            address(_auctionHouse),
            abi.encodeWithSelector(IAuctionHouse.lotRouting.selector, _lotId),
            abi.encode(
                _SELLER,
                _BASE_TOKEN,
                _QUOTE_TOKEN,
                toVeecode("01FPSA"),
                _LOT_CAPACITY,
                address(_allowlist),
                toVeecode(""),
                false,
                abi.encode("")
            )
        );
    }

    modifier givenAtomicOnCreate() {
        // Mock the Routing value on the auction house
        _mockLotRouting();

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

    function _onPurchase(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        uint256 allocatedAmount_
    ) internal {
        vm.prank(address(_auctionHouse));
        _allowlist.onPurchase(
            lotId_, buyer_, amount_, 0, false, abi.encode(_merkleProof, allocatedAmount_)
        );
    }

    // onCreate
    // [X] when the allowlist parameters are in an incorrect format
    //  [X] it reverts
    // [X] if the caller is not the auction house
    //  [X] it reverts
    // [X] if the seller is not the seller for the allowlist
    //  [X] it sets the merkle root and buyer limit
    // [X] if the lot is already registered
    //  [X] it reverts
    // [X] it sets the merkle root and buyer limit

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
            abi.encode(_MERKLE_ROOT, 1e18)
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
    // [X] when the allowlist parameters are in an incorrect format
    //  [X] it reverts
    // [X] if the caller is not the auction house
    //  [X] it reverts
    // [X] if the lot is not registered
    //  [X] it reverts
    // [X] if the buyer is not in the merkle tree
    //  [X] it reverts
    // [X] if the amount is greater than the buyer limit
    //  [X] it reverts
    // [X] if the previous buyer spent plus the amount is greater than the buyer limit
    //  [X] it reverts
    // [X] when the buyer has a 0 limit
    //  [X] it reverts
    // [X] it updates the buyer spent

    function test_onPurchase_allowlistParametersIncorrectFormat_reverts()
        public
        givenAtomicOnCreate
    {
        // Expect revert
        vm.expectRevert();

        vm.prank(address(_auctionHouse));
        _allowlist.onPurchase(_lotId, _BUYER, 1e18, 0, false, abi.encode(_MERKLE_ROOT, 1e18, 2e18));
    }

    function test_onPurchase_callerNotAuctionHouse_reverts() public givenAtomicOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _allowlist.onPurchase(
            _lotId, _BUYER, 1e18, 0, false, abi.encode(_merkleProof, _BUYER_ALLOCATED_AMOUNT)
        );
    }

    function test_onPurchase_lotNotRegistered_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER, 1e18, _BUYER_ALLOCATED_AMOUNT);
    }

    function test_onPurchase_buyerNotInMerkleTree_reverts() public givenAtomicOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER_THREE, 1e18, _BUYER_ALLOCATED_AMOUNT);
    }

    function test_onPurchase_amountGreaterThanBuyerLimit_reverts() public givenAtomicOnCreate {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(AllocatedMerkleAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER, _BUYER_ALLOCATED_AMOUNT + 1, _BUYER_ALLOCATED_AMOUNT);
    }

    function test_onPurchase_buyerHasZeroLimit_reverts() public givenAtomicOnCreate {
        // Set the merkle proof
        _merkleProof = new bytes32[](1);
        _merkleProof[0] =
            bytes32(0xe0a73973cd60d8cbabb978d1f3c983065148b388619b9176d3d30e47c16d4fd5);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(AllocatedMerkleAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, address(0x0000000000000000000000000000000000000020), 1, 0);
    }

    function test_onPurchase_previousBuyerSpentPlusAmountGreaterThanBuyerLimit_reverts()
        public
        givenAtomicOnCreate
    {
        _onPurchase(_lotId, _BUYER, _BUYER_ALLOCATED_AMOUNT, _BUYER_ALLOCATED_AMOUNT);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(AllocatedMerkleAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER, 1, _BUYER_ALLOCATED_AMOUNT);
    }

    function test_onPurchase(
        uint256 amount_
    ) public givenAtomicOnCreate {
        uint256 amount = bound(amount_, 1, _BUYER_ALLOCATED_AMOUNT);

        _onPurchase(_lotId, _BUYER, amount, _BUYER_ALLOCATED_AMOUNT);

        assertEq(_allowlist.lotBuyerSpent(_lotId, _BUYER), amount, "lotBuyerSpent");
    }

    // setMerkleRoot
    // [X] when the caller is not the lot seller
    //  [X] it reverts
    // [X] when the lot is not registered
    //  [X] it reverts
    // [X] the merkle root is updated

    function test_setMerkleRoot_callerNotSeller() public givenAtomicOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _allowlist.setMerkleRoot(_lotId, _MERKLE_ROOT);
    }

    function test_setMerkleRoot_lotNotRegistered_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        vm.prank(_SELLER);
        _allowlist.setMerkleRoot(_lotId, _MERKLE_ROOT);
    }

    function test_setMerkleRoot() public givenAtomicOnCreate {
        bytes32 newMerkleRoot = 0x0fdc3942d9af344db31ff2e80c06bc4e558dc967ca5b4d421d741870f5ea40df;

        vm.prank(_SELLER);
        _allowlist.setMerkleRoot(_lotId, newMerkleRoot);

        assertEq(_allowlist.lotMerkleRoot(_lotId), newMerkleRoot, "lotMerkleRoot");
    }
}
