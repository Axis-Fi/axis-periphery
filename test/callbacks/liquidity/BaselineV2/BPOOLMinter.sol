// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Owned} from "@solmate-6.7.0/auth/Owned.sol";

import {Kernel, Keycode, toKeycode, Policy, Permissions} from "@baseline/Kernel.sol";
import {BPOOLv1} from "@baseline/modules/BPOOL.v1.sol";
import {CREDTv1} from "@baseline/modules/CREDT.v1.sol";

contract BPOOLMinter is Policy, Owned {
    // solhint-disable var-name-mixedcase
    BPOOLv1 public BPOOL;
    CREDTv1 public CREDT;
    // solhint-enable var-name-mixedcase

    constructor(
        Kernel kernel_
    ) Policy(kernel_) Owned(kernel_.executor()) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("BPOOL");
        dependencies[1] = toKeycode("CREDT");

        BPOOL = BPOOLv1(getModuleAddress(toKeycode("BPOOL")));
        CREDT = CREDTv1(getModuleAddress(toKeycode("CREDT")));
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](3);
        requests[0] = Permissions(toKeycode("BPOOL"), BPOOL.mint.selector);
        requests[1] = Permissions(toKeycode("BPOOL"), BPOOL.setTransferLock.selector);
        requests[2] = Permissions(toKeycode("CREDT"), CREDT.updateCreditAccount.selector);
    }

    function mint(address to_, uint256 amount_) external onlyOwner {
        BPOOL.mint(to_, amount_);
    }

    function setTransferLock(
        bool lock_
    ) external onlyOwner {
        BPOOL.setTransferLock(lock_);
    }

    /// @notice Mimics allocating credit (call options) to a user
    function allocateCreditAccount(address user_, uint256 amount_, uint256 days_) external {
        // Transfer collateral
        BPOOL.transferFrom(user_, address(this), amount_);

        // Calculate the amount of debt to record against the collateral
        uint256 debt = amount_ * BPOOL.getBaselineValue() / 1e18;

        // Approve spending
        BPOOL.approve(address(CREDT), amount_);

        // Update credit account
        CREDT.updateCreditAccount(user_, amount_, debt, block.timestamp + days_ * 1 days);
    }
}
