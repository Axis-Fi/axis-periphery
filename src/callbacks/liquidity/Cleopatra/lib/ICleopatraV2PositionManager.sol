// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

/// @dev Generated from https://arbiscan.io/address/0xac9d1dfa5483ebb06e623df31547b2a4dc8bf7ca
interface ICleopatraV2PositionManager {
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
        uint256 veRamTokenId;
    }

    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Collect(uint256 indexed tokenId, address recipient, uint256 amount0, uint256 amount1);
    event DecreaseLiquidity(
        uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1
    );
    event IncreaseLiquidity(
        uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1
    );
    event SwitchAttachment(
        uint256 indexed tokenId, uint256 oldVeRamTokenId, uint256 newVeRamTokenId
    );
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    receive() external payable;

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external view returns (bytes32);
    function WETH9() external view returns (address);
    function approve(address to, uint256 tokenId) external;
    function balanceOf(address owner) external view returns (uint256);
    function baseURI() external pure returns (string memory);
    function batchSwitchAttachment(uint256[] memory tokenIds, uint256 veRamTokenId) external;
    function burn(uint256 tokenId) external payable;
    function collect(CollectParams memory params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);
    function decreaseLiquidity(DecreaseLiquidityParams memory params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
    function factory() external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function getReward(uint256 tokenId, address[] memory tokens) external;
    function increaseLiquidity(IncreaseLiquidityParams memory params)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);
    function initialize() external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function mint(MintParams memory params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function multicall(bytes[] memory data) external payable returns (bytes[] memory results);
    function name() external view returns (string memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function permit(
        address spender,
        uint256 tokenId,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable;
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
    function cleopatraV2MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes memory data
    ) external;
    function refundETH() external payable;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) external;
    function selfPermit(
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable;
    function selfPermitAllowed(
        address token,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable;
    function selfPermitAllowedIfNecessary(
        address token,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable;
    function selfPermitIfNecessary(
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable;
    function setApprovalForAll(address operator, bool approved) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function sweepToken(address token, uint256 amountMinimum, address recipient) external payable;
    function switchAttachment(uint256 tokenId, uint256 veRamTokenId) external;
    function symbol() external view returns (string memory);
    function timelock() external pure returns (address _timelock);
    function tokenByIndex(uint256 index) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function unwrapWETH9(uint256 amountMinimum, address recipient) external payable;
    function veRam() external view returns (address);
    function voter() external pure returns (address _voter);
}
