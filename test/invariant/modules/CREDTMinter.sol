// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Owned} from "@solmate-6.7.0/auth/Owned.sol";
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";

import {Kernel, Keycode, toKeycode, Policy, Permissions} from "@baseline/Kernel.sol";
import {CREDTv1} from "./CREDT.v1.sol";

contract CREDTMinter is Policy, Owned {
    CREDTv1 public CREDT;

    constructor(Kernel kernel_) Policy(kernel_) Owned(kernel_.executor()) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("CREDT");

        CREDT = CREDTv1(getModuleAddress(toKeycode("CREDT")));
    }
}
