// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

/// @dev Generated from https://arbiscan.io/address/0xf896d16fa56a625802b6013f9f9202790ec69908
interface IRamsesV2Factory {
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);
    event FeeCollectorChanged(address indexed oldFeeCollector, address indexed newFeeCollector);
    event FeeSetterChanged(address indexed oldSetter, address indexed newSetter);
    event ImplementationChanged(
        address indexed oldImplementation, address indexed newImplementation
    );
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool
    );
    event SetFeeProtocol(
        uint8 feeProtocol0Old, uint8 feeProtocol1Old, uint8 feeProtocol0New, uint8 feeProtocol1New
    );
    event SetPoolFeeProtocol(
        address pool,
        uint8 feeProtocol0Old,
        uint8 feeProtocol1Old,
        uint8 feeProtocol0New,
        uint8 feeProtocol1New
    );

    function POOL_INIT_CODE_HASH() external view returns (bytes32);
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
    function feeAmountTickSpacing(uint24) external view returns (int24);
    function feeCollector() external view returns (address);
    function feeProtocol() external view returns (uint8);
    function feeSetter() external view returns (address);
    function getPool(address, address, uint24) external view returns (address);
    function implementation() external view returns (address);
    function initialize(
        address _nfpManager,
        address _veRam,
        address _voter,
        address _implementation
    ) external;
    function nfpManager() external view returns (address);
    function owner() external view returns (address);
    function poolFeeProtocol(address pool) external view returns (uint8 __poolFeeProtocol);
    function setFee(address _pool, uint24 _fee) external;
    function setFeeCollector(address _feeCollector) external;
    function setFeeProtocol(uint8 _feeProtocol) external;
    function setFeeSetter(address _newFeeSetter) external;
    function setImplementation(address _implementation) external;
    function setOwner(address _owner) external;
    function setPoolFeeProtocol(address pool, uint8 _feeProtocol) external;
    function setPoolFeeProtocol(address pool, uint8 feeProtocol0, uint8 feeProtocol1) external;
    function veRam() external view returns (address);
    function voter() external view returns (address);
}
