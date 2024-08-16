// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Kernel, Module, Keycode, toKeycode} from "@baseline/Kernel.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {FixedPoint96} from "v3-core/libraries/FixedPoint96.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";

// Liquidity range
enum Range {
    FLOOR,
    ANCHOR,
    DISCOVERY
}

struct Ticks {
    int24 lower;
    int24 upper;
}

struct Position {
    uint128 liquidity;
    uint160 sqrtPriceL;
    uint160 sqrtPriceU;
    uint256 bAssets;
    uint256 reserves;
    uint256 capacity;
}

/// @title  Baseline's UniswapV3 Liquidity Pool Management Module
contract BPOOLv1 is Module, ERC20 {
    using SafeTransferLib for ERC20;

    //============================================================================================//
    //                                      MODULE SETUP                                          //
    //============================================================================================//

    constructor(
        Kernel _kernel,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _factory,
        address _reserve,
        uint24 _feeTier,
        int24 _initialActiveTick
    ) Module(_kernel) ERC20(_name, _symbol, _decimals) {
        reserve = ERC20(_reserve);
        FEE_TIER = _feeTier;
        TICK_SPACING = IUniswapV3Factory(_factory).feeAmountTickSpacing(FEE_TIER);
        pool = IUniswapV3Pool(
            IUniswapV3Factory(_factory).createPool(address(this), address(reserve), FEE_TIER)
        );

        // Set the initial price to the active tick
        pool.initialize(TickMath.getSqrtRatioAtTick(_initialActiveTick));

        locked = true;
    }

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("BPOOL");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    // ========= ERRORS ========= //

    error TransferLocked();
    error InvalidAction();
    error InvalidCaller();
    error InvalidTickRange();

    // ========= STATE ========= //

    // Constants
    int24 public immutable TICK_SPACING;
    uint24 public immutable FEE_TIER;

    // Dependencies
    IUniswapV3Pool public immutable pool;
    ERC20 public immutable reserve; // The reserve token contract: WETH

    bool public locked;

    mapping(Range => Ticks) public getTicks;
    mapping(Range => uint128) public getLiquidity;

    // ========= PERMISSIONED WRITE FUNCTIONS ========= //

    // UniswapV3Pool.sol callback on liquidity operations (mint/burn)
    function uniswapV3MintCallback(
        uint256 _bAssetsOwed,
        uint256 _reservesOwed,
        bytes calldata _data
    ) external {
        if (msg.sender != address(pool)) revert InvalidCaller();

        (address payer) = abi.decode(_data, (address));

        if (_bAssetsOwed > 0) {
            _mint(address(pool), _bAssetsOwed);
        }

        if (_reservesOwed > 0) {
            reserve.safeTransferFrom(payer, address(pool), _reservesOwed);
        }
    }

    function addReservesTo(
        Range _range,
        uint256 _reserves
    )
        external
        permissioned
        returns (uint256 bAssetsAdded_, uint256 reservesAdded_, uint128 liquidityFinal_)
    {
        // If invalid tick boundaries or reserves are zero return early to avoid revert
        Ticks memory ticks = getTicks[_range];

        if (ticks.lower == ticks.upper || _reserves == 0) return (0, 0, 0);

        // Find the liquidity amount for the given reserves supplied into the range
        uint128 liquidity = _getLiquidityOptimistic(ticks.lower, ticks.upper, _reserves);
        (bAssetsAdded_, reservesAdded_) = pool.mint(
            address(this),
            ticks.lower,
            ticks.upper,
            liquidity,
            abi.encode(msg.sender) // sender is the payer
        );

        // Save and return the most up to date liquidity value
        liquidityFinal_ = _getLiquidity(ticks.lower, ticks.upper);
        getLiquidity[_range] = liquidityFinal_;
    }

    function addLiquidityTo(
        Range _range,
        uint128 _liquidity
    )
        external
        permissioned
        returns (uint256 bAssetsAdded_, uint256 reservesAdded_, uint128 liquidityFinal_)
    {
        Ticks memory ticks = getTicks[_range];
        if (ticks.lower == ticks.upper || _liquidity == 0) return (0, 0, 0);

        (bAssetsAdded_, reservesAdded_) = pool.mint(
            address(this),
            ticks.lower,
            ticks.upper,
            _liquidity,
            abi.encode(msg.sender) // sender is the payer
        );

        liquidityFinal_ = _getLiquidity(ticks.lower, ticks.upper);
        getLiquidity[_range] = liquidityFinal_;
    }

    function removeAllFrom(Range _range)
        external
        permissioned
        returns (
            uint256 bAssetsRemoved_,
            uint256 bAssetFees_,
            uint256 reservesRemoved_,
            uint256 reserveFees_
        )
    {
        Ticks memory ticks = getTicks[_range];
        uint128 liquidityToRemove = _getLiquidity(ticks.lower, ticks.upper);
        uint128 currentLiquidity = getLiquidity[_range];

        if (liquidityToRemove == 0) return (0, 0, 0, 0);

        uint256 bAssetsRemoved;
        uint256 bAssetFees;
        uint256 reservesRemoved;
        uint256 reserveFees;

        // remove any extra unexpected liquidity as fees (i.e. donated)
        if (liquidityToRemove > currentLiquidity) {
            (bAssetsRemoved, bAssetFees, reservesRemoved, reserveFees) =
                _removeLiquidity(ticks.lower, ticks.upper, liquidityToRemove - currentLiquidity);

            bAssetFees_ += bAssetsRemoved + bAssetFees;
            reserveFees_ += reservesRemoved + reserveFees;
        }

        liquidityToRemove = currentLiquidity;
        if (liquidityToRemove == 0) return (0, bAssetFees_, 0, reserveFees_);

        (bAssetsRemoved, bAssetFees, reservesRemoved, reserveFees) =
            _removeLiquidity(ticks.lower, ticks.upper, liquidityToRemove);

        bAssetsRemoved_ += bAssetsRemoved;
        bAssetFees_ += bAssetFees;
        reservesRemoved_ += reservesRemoved;
        reserveFees_ += reserveFees;

        getLiquidity[_range] = 0;
    }

    function setTicks(Range _range, int24 _lower, int24 _upper) external permissioned {
        // allow lower == upper to handle when anchor does not exist
        if (_lower > _upper) revert InvalidTickRange();

        getTicks[_range] = Ticks({lower: _lower, upper: _upper});
    }

    function setTransferLock(bool _lock) external permissioned {
        locked = _lock;
    }

    function transfer(address _to, uint256 _amount) public override returns (bool) {
        if (locked) revert TransferLocked();
        return super.transfer(_to, _amount);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) public override returns (bool) {
        if (locked) revert TransferLocked();
        return super.transferFrom(_from, _to, _amount);
    }

    function mint(address _to, uint256 _amount) external permissioned {
        _mint(_to, _amount);
    }

    /// @notice  Burns excess bAssets not used in the pool POL. Can be called by anyone.
    function burnAllBAssetsInContract() external {
        _burn(address(this), balanceOf[address(this)]);
    }

    // --- View Functions ------------------------------------------------------ //

    /// @notice  Returns the price at the lower tick of the floor position
    function getBaselineValue() public view returns (uint256) {
        uint160 sqrtPriceA = TickMath.getSqrtRatioAtTick(getTicks[Range.FLOOR].lower);
        uint256 sqrtPriceScaled = FixedPointMathLib.divWad(sqrtPriceA, FixedPoint96.Q96);
        return FixedPointMathLib.mulWad(sqrtPriceScaled, sqrtPriceScaled);
    }

    /// @notice Returns the closest tick spacing boundary above the active tick
    ///         Formerly "upperAnchorTick"
    function getActiveTS() public view returns (int24 activeTS_) {
        (, int24 activeTick,,,,,) = pool.slot0();

        // Round down to the nearest active tick spacing
        activeTS_ = ((activeTick / TICK_SPACING) * TICK_SPACING);

        // Properly handle negative numbers and edge cases
        if (activeTick >= 0 || activeTick % TICK_SPACING == 0) {
            activeTS_ += TICK_SPACING;
        }
    }

    /// @notice  Wrapper for liquidity data struct
    function getPosition(Range _range) public view returns (Position memory position_) {
        Ticks memory ticks = getTicks[_range];
        position_.liquidity = getLiquidity[_range];

        position_.sqrtPriceL = TickMath.getSqrtRatioAtTick(ticks.lower);
        position_.sqrtPriceU = TickMath.getSqrtRatioAtTick(ticks.upper);

        (position_.bAssets, position_.reserves) =
            getBalancesForLiquidity(position_.sqrtPriceL, position_.sqrtPriceU, position_.liquidity);

        (uint160 sqrtPriceA,,,,,,) = pool.slot0();

        position_.capacity = getCapacityForLiquidity(
            position_.sqrtPriceL, position_.sqrtPriceU, position_.liquidity, sqrtPriceA
        );
    }

    function getBalancesForLiquidity(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint128 _liquidity
    ) public view returns (uint256 bAssets_, uint256 reserves_) {
        (uint160 sqrtPriceA,,,,,,) = pool.slot0();

        (bAssets_, reserves_) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceA, _sqrtPriceL, _sqrtPriceU, _liquidity
        );
    }

    // based on the current active price
    function getLiquidityForReserves(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint256 _reserves,
        uint160 _sqrtPriceA
    ) public pure returns (uint128 liquidity_) {
        uint160 upperPrice = min(_sqrtPriceA, _sqrtPriceU);
        if (upperPrice <= _sqrtPriceL) return 0;

        liquidity_ = LiquidityAmounts.getLiquidityForAmount1(_sqrtPriceL, upperPrice, _reserves);
    }

    function getCapacityForLiquidity(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint128 _liquidity,
        uint160 _sqrtPriceA
    ) public pure returns (uint256 capacity_) {
        if (_sqrtPriceA >= _sqrtPriceL) {
            capacity_ = LiquidityAmounts.getAmount0ForLiquidity(
                _sqrtPriceL, min(_sqrtPriceU, _sqrtPriceA), _liquidity
            );
        }
    }

    // based on the current active price
    function getCapacityForReserves(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint256 _reserves
    ) public view returns (uint256 capacity_) {
        (uint160 sqrtPriceA,,,,,,) = pool.slot0();
        capacity_ = getCapacityForLiquidity(
            _sqrtPriceL,
            _sqrtPriceU,
            getLiquidityForReserves(_sqrtPriceL, _sqrtPriceU, _reserves, sqrtPriceA),
            sqrtPriceA
        );
    }

    function getCapacityForReservesAtPrice(
        uint160 _sqrtPriceL,
        uint160 _sqrtPriceU,
        uint256 _reserves,
        uint160 _targetSqrtPrice
    ) public pure returns (uint256 capacity_) {
        capacity_ = getCapacityForLiquidity(
            _sqrtPriceL,
            _sqrtPriceU,
            getLiquidityForReserves(_sqrtPriceL, _sqrtPriceU, _reserves, _targetSqrtPrice),
            _targetSqrtPrice
        );
    }

    // --- Internal Library ---------------------------------------------------- //

    /// @notice  Returns the liquidity stored in the pool of a given range of tick boundaries
    function _getLiquidity(int24 _lower, int24 _upper) internal view returns (uint128 liquidity_) {
        bytes32 key = keccak256(abi.encodePacked(address(this), _lower, _upper));
        (liquidity_,,,,) = pool.positions(key);
    }

    /// @notice Internal function to remove liquidity and send to caller
    /// @dev    This function will also collect any fees from the position
    function _removeLiquidity(
        int24 _lower,
        int24 _upper,
        uint128 _liquidity
    )
        internal
        returns (uint256 bAssetPOL_, uint256 bAssetFees_, uint256 reservePOL_, uint256 reserveFees_)
    {
        if (_liquidity == 0) return (0, 0, 0, 0);
        (bAssetPOL_, reservePOL_) = pool.burn(_lower, _upper, _liquidity);

        (uint256 bAssetsRemoved, uint256 reservesRemoved) =
            pool.collect(msg.sender, _lower, _upper, type(uint128).max, type(uint128).max);

        bAssetFees_ = bAssetsRemoved - bAssetPOL_;
        reserveFees_ = reservesRemoved - reservePOL_;

        // Burn all bAssets sent to recipient (except fees)
        _burn(msg.sender, bAssetPOL_);
    }

    // Same logic as getLiquidityForAmounts, except when sqrtRatioX96 is within range of sqrtRatioAX96 and sqrtRatioBX96
    // Warning this was simplfied from the original implementation of getLiquidityOptimisitic.
    function _getLiquidityOptimistic(
        int24 _lower,
        int24 _upper,
        uint256 _reserves
    ) internal view returns (uint128 newLiquidity_) {
        (uint160 sqrtPriceA,,,,,,) = pool.slot0();

        uint160 sqrtPriceL = TickMath.getSqrtRatioAtTick(_lower);
        uint160 sqrtPriceU = TickMath.getSqrtRatioAtTick(_upper);

        newLiquidity_ = LiquidityAmounts.getLiquidityForAmount1(
            sqrtPriceL, sqrtPriceA < sqrtPriceU ? sqrtPriceA : sqrtPriceU, _reserves
        );
    }

    // --- Util Wrappers ------------------------------------------------------ //
    function min(uint160 a, uint160 b) internal pure returns (uint160) {
        return uint160(FixedPointMathLib.min(uint256(a), uint256(b)));
    }

    function max(uint160 a, uint160 b) internal pure returns (uint160) {
        return uint160(FixedPointMathLib.max(uint256(a), uint256(b)));
    }
}
