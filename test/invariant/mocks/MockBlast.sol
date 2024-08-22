// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

enum YieldMode {
    AUTOMATIC,
    VOID,
    CLAIMABLE
}

enum GasMode {
    VOID,
    CLAIMABLE
}

contract MockBlast {
    function configure(YieldMode _yield, GasMode gasMode, address governor) external {}
}
