// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Owned} from "@solmate-6.7.0/auth/Owned.sol";

import {Kernel, Keycode, toKeycode, Policy, Permissions} from "@baseline/Kernel.sol";
import {BPOOLv1} from "@baseline/modules/BPOOL.v1.sol";

contract BPOOLMinter is Policy, Owned {
    BPOOLv1 public BPOOL;

    constructor(
        Kernel kernel_
    ) Policy(kernel_) Owned(kernel_.executor()) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("BPOOL");

        BPOOL = BPOOLv1(getModuleAddress(toKeycode("BPOOL")));
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](2);
        requests[0] = Permissions(toKeycode("BPOOL"), BPOOL.mint.selector);
        requests[1] = Permissions(toKeycode("BPOOL"), BPOOL.setTransferLock.selector);
    }

    function mint(address to_, uint256 amount_) external onlyOwner {
        BPOOL.mint(to_, amount_);
    }

    function setTransferLock(
        bool lock_
    ) external onlyOwner {
        BPOOL.setTransferLock(lock_);
    }
}
