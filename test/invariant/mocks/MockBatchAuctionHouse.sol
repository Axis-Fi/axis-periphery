// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BatchAuctionHouse} from "@axis-core-1.0.4/BatchAuctionHouse.sol";

import {Veecode} from "@axis-core-1.0.4/modules/Modules.sol";

contract MockBatchAuctionHouse is BatchAuctionHouse {
    constructor(
        address owner_,
        address protocol_,
        address permit2_
    ) BatchAuctionHouse(owner_, protocol_, permit2_) {}

    function setLotCounter(uint96 newLotCounter) public {
        lotCounter = newLotCounter;
    }

    function setAuctionReference(uint96 lotId_, Veecode auctionReference) public {
        lotRouting[lotId_].auctionReference = auctionReference;
    }
}
