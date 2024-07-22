// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

/// @dev Generated from https://arbiscan.io/address/0xaa9b8a7430474119a442ef0c2bf88f7c3c776f2f
interface IRamsesV1Factory {
    event Initialized(uint8 version);
    event PairCreated(
        address indexed token0, address indexed token1, bool stable, address pair, uint256
    );
    event SetFee(bool stable, uint256 fee);
    event SetFeeSplit(uint8 toFeesOld, uint8 toTreasuryOld, uint8 toFeesNew, uint8 toTreasuryNew);
    event SetPairFee(address pair, uint256 fee);
    event SetPoolFeeSplit(
        address pool, uint8 toFeesOld, uint8 toTreasuryOld, uint8 toFeesNew, uint8 toTreasuryNew
    );

    function MAX_FEE() external view returns (uint256);
    function acceptFeeManager() external;
    function acceptPauser() external;
    function allPairs(uint256) external view returns (address);
    function allPairsLength() external view returns (uint256);
    function createPair(
        address tokenA,
        address tokenB,
        bool stable
    ) external returns (address pair);
    function feeManager() external view returns (address);
    function feeSplit() external view returns (uint8);
    function getFee(bool _stable) external view returns (uint256);
    function getPair(address, address, bool) external view returns (address);
    function getPoolFeeSplit(address _pool) external view returns (uint8 _poolFeeSplit);
    function initialize(
        address _proxyAdmin,
        address _pairImplementation,
        address _voter,
        address msig
    ) external;
    function initializeTreasury() external;
    function isPair(address) external view returns (bool);
    function isPaused() external view returns (bool);
    function pairCodeHash() external view returns (bytes32);
    function pairFee(address _pool) external view returns (uint256 fee);
    function pairImplementation() external view returns (address);
    function pauser() external view returns (address);
    function pendingFeeManager() external view returns (address);
    function pendingPauser() external view returns (address);
    function proxyAdmin() external view returns (address);
    function setFee(bool _stable, uint256 _fee) external;
    function setFeeManager(address _feeManager) external;
    function setFeeSplit(uint8 _toFees, uint8 _toTreasury) external;
    function setImplementation(address _implementation) external;
    function setPairFee(address _pair, uint256 _fee) external;
    function setPause(bool _state) external;
    function setPauser(address _pauser) external;
    function setPoolFeeSplit(address _pool, uint8 _toFees, uint8 _toTreasury) external;
    function setTreasury(address _treasury) external;
    function stableFee() external view returns (uint256);
    function treasury() external view returns (address);
    function volatileFee() external view returns (uint256);
    function voter() external view returns (address);
}
