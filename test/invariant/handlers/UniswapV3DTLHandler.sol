// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BeforeAfter} from "../helpers/BeforeAfter.sol";
import {Assertions} from "../helpers/Assertions.sol";

import {Callbacks} from "@axis-core-1.0.1/lib/Callbacks.sol";
import {Permit2User} from "@axis-core-1.0.1-test/lib/permit2/Permit2User.sol";

import {IAuction} from "@axis-core-1.0.1/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "@axis-core-1.0.1/interfaces/IAuctionHouse.sol";
import {BatchAuctionHouse} from "@axis-core-1.0.1/BatchAuctionHouse.sol";
import {ILinearVesting} from "@axis-core-1.0.1/interfaces/modules/derivatives/ILinearVesting.sol";

import {GUniFactory} from "@g-uni-v1-core-0.9.9/GUniFactory.sol";
import {GUniPool} from "@g-uni-v1-core-0.9.9/GUniPool.sol";
import {IUniswapV3Pool} from
    "@uniswap-v3-core-1.0.1-solc-0.8-simulate/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "../modules/uniswapv3-periphery/interfaces/ISwapRouter.sol";
import {IUniswapV3Factory} from
    "@uniswap-v3-core-1.0.1-solc-0.8-simulate/interfaces/IUniswapV3Factory.sol";
import {SqrtPriceMath} from "../../../src/lib/uniswap-v3/SqrtPriceMath.sol";

import {BaseDirectToLiquidity} from "../../../src//callbacks/liquidity/BaseDTL.sol";
import {BaseCallback} from "@axis-core-1.0.1/bases/BaseCallback.sol";
import {BaseDirectToLiquidity} from "../../../src/callbacks/liquidity/BaseDTL.sol";
import {UniswapV3DirectToLiquidity} from "../../../src/callbacks/liquidity/UniswapV3DTL.sol";
import {LinearVesting} from "@axis-core-1.0.1/modules/derivatives/LinearVesting.sol";
import {MockBatchAuctionModule} from
    "@axis-core-1.0.1-test/modules/Auction/MockBatchAuctionModule.sol";

import {keycodeFromVeecode, toKeycode} from "@axis-core-1.0.1/modules/Keycode.sol";

import {MockERC20} from "@solmate-6.7.0/test/utils/mocks/MockERC20.sol";
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";
import {FixedPointMathLib} from "@solmate-6.7.0/utils/FixedPointMathLib.sol";

abstract contract UniswapV3DTLHandler is BeforeAfter, Assertions {
    /*//////////////////////////////////////////////////////////////////////////
                                HANDLER VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    uint24 internal _poolFee = 500;
    uint96 internal constant _PROCEEDS = 20e18;
    uint96 internal constant _REFUND = 0;

    uint96 internal _proceedsV3;
    uint96 internal _refundV3;
    uint96 internal _capacityUtilisedV3;
    uint96 internal _quoteTokensToDepositV3;
    uint96 internal _baseTokensToDepositV3;
    uint96 internal _curatorPayoutV3;
    uint24 internal _maxSlippageV3 = 1;
    uint256 internal _additionalQuoteTokensMinted;

    uint160 internal _sqrtPriceX96;

    BaseDirectToLiquidity.OnCreateParams internal _dtlCreateParamsV3;
    UniswapV3DirectToLiquidity.UniswapV3OnCreateParams internal _uniswapV3CreateParams;

    mapping(uint96 => bool) internal isLotFinishedV3;

    mapping(uint96 => BaseDirectToLiquidity.OnCreateParams) internal lotIdCreationParamsV3;

    /*//////////////////////////////////////////////////////////////////////////
                                TARGET FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function uniswapV3DTL_createLot(
        uint256 sellerIndexSeed,
        uint24 poolPercent,
        uint48 vestingStart,
        uint48 vestingExpiry
    ) public {
        // PRE-CONDITIONS
        address seller_ = randomAddress(sellerIndexSeed);

        __before(0, seller_, _dtlV3Address);

        poolPercent = uint24(bound(uint256(poolPercent), 10e2, 100e2));
        vestingStart = uint48(
            bound(
                uint256(vestingStart), uint48(block.timestamp) + 2 days, uint256(type(uint48).max)
            )
        );
        vestingExpiry = uint48(
            bound(uint256(vestingStart), uint256(vestingStart + 1), uint256(type(uint48).max))
        );
        _maxSlippageV3 = uint24(bound(uint256(_maxSlippageV3), 1, 100e2));

        if (vestingStart == vestingExpiry) return;

        _uniswapV3CreateParams = UniswapV3DirectToLiquidity.UniswapV3OnCreateParams({
            poolFee: _poolFee,
            maxSlippage: _maxSlippageV3 // 0.01%, to handle rounding errors
        });

        _dtlCreateParamsV3 = BaseDirectToLiquidity.OnCreateParams({
            poolPercent: poolPercent,
            vestingStart: vestingStart,
            vestingExpiry: vestingExpiry,
            recipient: seller_,
            implParams: abi.encode(_uniswapV3CreateParams)
        });

        // Mint and approve the capacity to the owner
        _baseToken.mint(seller_, _LOT_CAPACITY);
        vm.prank(seller_);
        _baseToken.approve(address(_auctionHouse), _LOT_CAPACITY);

        // Prep the lot arguments
        IAuctionHouse.RoutingParams memory routingParams = IAuctionHouse.RoutingParams({
            auctionType: keycodeFromVeecode(_batchAuctionModule.VEECODE()),
            baseToken: address(_baseToken),
            quoteToken: address(_quoteToken),
            referrerFee: 0, // No referrer fee
            curator: address(0),
            callbacks: _dtlV3,
            callbackData: abi.encode(_dtlCreateParamsV3),
            derivativeType: toKeycode(""),
            derivativeParams: abi.encode(""),
            wrapDerivative: false
        });

        IAuction.AuctionParams memory auctionParams = IAuction.AuctionParams({
            start: uint48(block.timestamp) + 1,
            duration: 1 days,
            capacityInQuote: false,
            capacity: _LOT_CAPACITY,
            implParams: abi.encode("")
        });

        // Create a new lot
        vm.prank(seller_);
        try _auctionHouse.auction(routingParams, auctionParams, "") returns (uint96 lotIdCreated) {
            // POST-CONDITIONS
            __after(lotIdCreated, seller_, _dtlV2Address);

            equal(
                _after.dtlConfigV3.recipient,
                seller_,
                "AX-21: UniswapV3Dtl_onCreate() should set DTL Config recipient"
            );
            equal(
                _after.dtlConfigV3.lotCapacity,
                _LOT_CAPACITY,
                "AX-22: UniswapV3Dtl_onCreate() should set DTL Config lotCapacity"
            );
            equal(
                _after.dtlConfigV3.lotCuratorPayout,
                0,
                "AX-23: UniswapV3Dtl_onCreate() should set DTL Config lotCuratorPayout"
            );
            equal(
                _after.dtlConfigV3.poolPercent,
                _dtlCreateParamsV3.poolPercent,
                "AX-24: UniswapV3Dtl_onCreate() should set DTL Config poolPercent"
            );
            equal(
                _after.dtlConfigV3.vestingStart,
                vestingStart,
                "AX-25: UniswapV3Dtl_onCreate() should set DTL Config vestingStart"
            );
            equal(
                _after.dtlConfigV3.vestingExpiry,
                vestingExpiry,
                "AX-26: UniswapV3Dtl_onCreate() should set DTL Config vestingExpiry"
            );
            equal(
                address(_after.dtlConfigV3.linearVestingModule),
                vestingStart == 0 ? address(0) : address(_linearVesting),
                "AX-27: UniswapV3Dtl_onCreate() should set DTL Config linearVestingModule"
            );
            equal(
                _after.dtlConfigV3.active,
                true,
                "AX-28: UniswapV3Dtl_onCreate() should set DTL Config active to true"
            );

            _assertBaseTokenBalancesV3();

            lotIdsV3.push(lotIdCreated);
            lotIdCreationParamsV3[lotIdCreated] = _dtlCreateParamsV3;
        } catch (bytes memory err) {
            bytes4[1] memory errors = [BaseDirectToLiquidity.Callback_Params_PoolExists.selector];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            assert(expected);
            return;
        }
    }

    struct OnCancelV3Temps {
        address seller;
        address sender;
        uint96 lotId;
    }

    function uniswapV3DTL_onCancel(uint256 senderIndexSeed, uint256 lotIndexSeed) public {
        // PRE-CONDITIONS
        OnCancelV3Temps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.lotId = randomLotIdV3(lotIndexSeed);
        (d.seller,,,,,,,,) = _auctionHouse.lotRouting(d.lotId);

        __before(d.lotId, d.seller, _dtlV3Address);
        if (_before.seller == address(0)) return;

        // ACTION
        vm.prank(address(_auctionHouse));
        try _dtlV3.onCancel(d.lotId, _REFUND_AMOUNT, false, abi.encode("")) {
            // POST-CONDITIONS
            __after(d.lotId, d.seller, _dtlV3Address);

            equal(
                _after.dtlConfigV3.active,
                false,
                "AX-11: DTL_onCancel() should set DTL Config active to false"
            );

            _assertBaseTokenBalancesV3();

            isLotFinishedV3[d.lotId] = true;
        } catch (bytes memory err) {
            bytes4[2] memory errors = [
                BaseDirectToLiquidity.Callback_Params_PoolExists.selector,
                BaseDirectToLiquidity.Callback_AlreadyComplete.selector
            ];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            assert(expected);
            return;
        }
    }

    struct OnCurateV3Temps {
        address seller;
        address sender;
        uint96 lotId;
    }

    function uniswapV3DTL_onCurate(uint256 senderIndexSeed, uint256 lotIndexSeed) public {
        // PRE-CONDITIONS
        OnCurateV3Temps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.lotId = randomLotIdV3(lotIndexSeed);
        (d.seller,,,,,,,,) = _auctionHouse.lotRouting(d.lotId);

        __before(d.lotId, d.seller, _dtlV3Address);
        if (_before.seller == address(0)) return;

        // ACTION
        vm.prank(address(_auctionHouse));
        try _dtlV3.onCurate(d.lotId, _PAYOUT_AMOUNT, false, abi.encode("")) {
            // POST-CONDITIONS
            __after(d.lotId, d.seller, _dtlV3Address);

            equal(
                _after.dtlConfigV3.lotCuratorPayout,
                _PAYOUT_AMOUNT,
                "AX-12: DTL_onCurate should set DTL Config lotCuratorPayout"
            );

            equal(
                _after.auctionHouseBaseBalance,
                (_LOT_CAPACITY * lotIdsV2.length) + (_LOT_CAPACITY * lotIdsV3.length),
                "AX-13: When calling DTL_onCurate auction house base token balance should be equal to lot Capacity of each lotId"
            );

            _assertBaseTokenBalancesV3();

            _capacityUtilisedV3 = _PAYOUT_AMOUNT;
        } catch (bytes memory err) {
            bytes4[2] memory errors = [
                BaseDirectToLiquidity.Callback_Params_PoolExists.selector,
                BaseDirectToLiquidity.Callback_AlreadyComplete.selector
            ];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            assert(expected);
            return;
        }
    }

    struct OnSettleV3Temps {
        address seller;
        address sender;
        uint96 lotId;
    }

    function uniswapV3DTL_onSettle(
        uint256 senderIndexSeed,
        uint256 lotIndexSeed,
        uint96 proceeds_,
        uint96 refund
    ) public {
        // PRE-CONDITIONS
        proceeds_ = uint96(bound(uint256(proceeds_), 2e18, 10e18));
        refund = uint96(bound(uint256(refund), 0, 1e18));
        _maxSlippageV3 = uint24(bound(uint256(_maxSlippageV3), 1, 100e2));

        OnSettleV3Temps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.lotId = randomLotIdV3(lotIndexSeed);
        (d.seller,,,,,,,,) = _auctionHouse.lotRouting(d.lotId);

        address pool = _createV3Pool();
        setV3CallbackParameters(d.lotId, _PROCEEDS, _REFUND);
        // _initializePool(pool, _sqrtPriceX96);

        __before(d.lotId, d.seller, _dtlV3Address);
        if (_before.seller == address(0)) return;
        if (isLotFinishedV3[d.lotId] == true) return;

        givenAddressHasQuoteTokenBalance(_dtlV3Address, _proceedsV3);
        givenAddressHasBaseTokenBalance(_before.seller, _capacityUtilisedV3);
        givenAddressHasBaseTokenAllowance(_before.seller, _dtlV3Address, _capacityUtilisedV3);

        // ACTION
        vm.prank(address(_auctionHouse));
        try _dtlV3.onSettle(d.lotId, _proceedsV3, _refundV3, abi.encode("")) {
            // POST-CONDITIONS
            __after(d.lotId, d.seller, _dtlV3Address);

            _assertPoolState(_sqrtPriceX96);
            _assertLpTokenBalanceV3(d.lotId, d.seller);
            if (_before.dtlConfigV3.vestingStart != 0) {
                _assertVestingTokenBalanceV3(d.lotId, d.seller);
            }
            _assertQuoteTokenBalanceV3();
            _assertBaseTokenBalanceV3();
            _assertApprovalsV3();

            isLotFinishedV3[d.lotId] = true;
        } catch (bytes memory err) {
            bytes4[2] memory errors = [
                UniswapV3DirectToLiquidity.Callback_Slippage.selector,
                BaseDirectToLiquidity.Callback_InsufficientBalance.selector
            ];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            assert(expected);
            return;
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _createV3Pool() internal returns (address) {
        (address token0, address token1) = address(_baseToken) < address(_quoteToken)
            ? (address(_baseToken), address(_quoteToken))
            : (address(_quoteToken), address(_baseToken));

        return _uniV3Factory.createPool(token0, token1, _poolFee);
    }

    function _getGUniPool() internal view returns (GUniPool) {
        // Get the pools deployed by the DTL callback
        address[] memory pools = _gUniFactory.getPools(_dtlV3Address);

        return GUniPool(pools[0]);
    }

    function _initializePool(address pool_, uint160 sqrtPriceX96_) internal {
        IUniswapV3Pool(pool_).initialize(sqrtPriceX96_);
    }

    function _calculateSqrtPriceX96(
        uint256 quoteTokenAmount_,
        uint256 baseTokenAmount_
    ) internal view returns (uint160) {
        return SqrtPriceMath.getSqrtPriceX96(
            address(_quoteToken), address(_baseToken), quoteTokenAmount_, baseTokenAmount_
        );
    }

    function setV3CallbackParameters(uint96 lotId, uint96 proceeds_, uint96 refund_) internal {
        _proceedsV3 = proceeds_;
        _refundV3 = refund_;

        // Calculate the capacity utilised
        // Any unspent curator payout is included in the refund
        // However, curator payouts are linear to the capacity utilised
        // Calculate the percent utilisation
        uint96 capacityUtilisationPercent = 100e2
            - uint96(FixedPointMathLib.mulDivDown(_refundV3, 100e2, _LOT_CAPACITY + _curatorPayoutV3));
        _capacityUtilisedV3 = _LOT_CAPACITY * capacityUtilisationPercent / 100e2;

        // The proceeds utilisation percent scales the quote tokens and base tokens linearly
        _quoteTokensToDepositV3 = _proceedsV3 * lotIdCreationParamsV3[lotId].poolPercent / 100e2;
        _baseTokensToDepositV3 =
            _capacityUtilisedV3 * lotIdCreationParamsV3[lotId].poolPercent / 100e2;

        _sqrtPriceX96 = _calculateSqrtPriceX96(_quoteTokensToDepositV3, _baseTokensToDepositV3);
    }

    function _getPool() internal view returns (address) {
        (address token0, address token1) = address(_baseToken) < address(_quoteToken)
            ? (address(_baseToken), address(_quoteToken))
            : (address(_quoteToken), address(_baseToken));
        return _uniV3Factory.getPool(token0, token1, _poolFee);
    }

    function _assertBaseTokenBalancesV3() internal {
        equal(
            _after.sellerBaseBalance,
            _before.sellerBaseBalance,
            "AX-09: DTL Callbacks should not change seller base token balance"
        );
        equal(
            _after.dtlBaseBalance,
            _before.dtlBaseBalance,
            "AX-10: DTL Callbacks should not change dtl base token balance"
        );
    }

    function _assertPoolState(
        uint160 sqrtPriceX96_
    ) internal {
        // Get the pool
        address pool = _getPool();

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        equal(
            sqrtPriceX96,
            sqrtPriceX96_,
            "AX-29: On UniswapV3DTL_OnSettle() calculated sqrt price should equal pool sqrt price"
        );
    }

    function _assertLpTokenBalanceV3(uint96 lotId, address seller) internal {
        // Get the pools deployed by the DTL callback
        GUniPool pool = _getGUniPool();

        uint256 sellerExpectedBalance;
        uint256 linearVestingExpectedBalance;
        // Only has a balance if not vesting
        if (lotIdCreationParamsV3[lotId].vestingStart == 0) {
            sellerExpectedBalance = pool.totalSupply();
        } else {
            linearVestingExpectedBalance = pool.totalSupply();
        }

        equal(
            pool.balanceOf(seller),
            lotIdCreationParamsV3[lotId].recipient == _SELLER ? sellerExpectedBalance : 0,
            "AX-14: DTL_onSettle should should credit seller the expected LP token balance"
        );
        equal(
            pool.balanceOf(address(_linearVesting)),
            linearVestingExpectedBalance,
            "AX-15: DTL_onSettle should should credit linearVestingModule the expected LP token balance"
        );
    }

    function _assertVestingTokenBalanceV3(uint96 lotId, address seller) internal {
        // Exit if not vesting
        if (lotIdCreationParamsV3[lotId].vestingStart == 0) {
            return;
        }

        // Get the pools deployed by the DTL callback
        address pool = address(_getGUniPool());

        // Get the wrapped address
        (, address wrappedVestingTokenAddress) = _linearVesting.deploy(
            pool,
            abi.encode(
                ILinearVesting.VestingParams({
                    start: lotIdCreationParamsV3[lotId].vestingStart,
                    expiry: lotIdCreationParamsV3[lotId].vestingExpiry
                })
            ),
            true
        );
        ERC20 wrappedVestingToken = ERC20(wrappedVestingTokenAddress);
        uint256 sellerExpectedBalance = wrappedVestingToken.totalSupply();

        equal(
            wrappedVestingToken.balanceOf(seller),
            sellerExpectedBalance,
            "AX-16: DTL_onSettle should should credit seller the expected wrapped vesting token balance"
        );
    }

    function _assertQuoteTokenBalanceV3() internal {
        equal(
            _quoteToken.balanceOf(_dtlV3Address),
            0,
            "AX-17: After DTL_onSettle DTL Address quote token balance should equal 0"
        );
    }

    function _assertBaseTokenBalanceV3() internal {
        equal(
            _baseToken.balanceOf(_dtlV3Address),
            0,
            "AX-18: After DTL_onSettle DTL Address base token balance should equal 0"
        );
    }

    function _assertApprovalsV3() internal {
        // Ensure there are no dangling approvals
        equal(
            _quoteToken.allowance(_dtlV3Address, address(_getGUniPool())),
            0,
            "AX-30: After UniswapV3DTL_onSettle DTL Address quote token allowance for GUniPool should equal 0"
        );
        equal(
            _baseToken.allowance(_dtlV3Address, address(_getGUniPool())),
            0,
            "AX-31: After UniswapV3DTL_onSettle DTL Address base token allowance for GUniPool should equal 0"
        );
    }
}
