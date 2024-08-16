// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BeforeAfter} from "../helpers/BeforeAfter.sol";
import {Assertions} from "../helpers/Assertions.sol";

import {Callbacks} from "@axis-core-1.0.0/lib/Callbacks.sol";
import {Permit2User} from "@axis-core-1.0.0-test/lib/permit2/Permit2User.sol";

import {IAuction} from "@axis-core-1.0.0/interfaces/modules/IAuction.sol";
import {IAuctionHouse} from "@axis-core-1.0.0/interfaces/IAuctionHouse.sol";
import {BatchAuctionHouse} from "@axis-core-1.0.0/BatchAuctionHouse.sol";
import {ILinearVesting} from "@axis-core-1.0.0/interfaces/modules/derivatives/ILinearVesting.sol";
import {IFixedPriceBatch} from "@axis-core-1.0.0/interfaces/modules/auctions/IFixedPriceBatch.sol";

import {GUniFactory} from "@g-uni-v1-core-0.9.9/GUniFactory.sol";
import {GUniPool} from "@g-uni-v1-core-0.9.9/GUniPool.sol";
import {IUniswapV3Pool} from
    "@uniswap-v3-core-1.0.1-solc-0.8-simulate/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from
    "@uniswap-v3-core-1.0.1-solc-0.8-simulate/interfaces/IUniswapV3Factory.sol";
import {SqrtPriceMath} from "../../../../src/lib/uniswap-v3/SqrtPriceMath.sol";

import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {BaselineAxisLaunch} from
    "../../../../src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";
import {UniswapV3DirectToLiquidity} from "../../../../src/callbacks/liquidity/UniswapV3DTL.sol";
import {LinearVesting} from "@axis-core-1.0.0/modules/derivatives/LinearVesting.sol";
import {MockBatchAuctionModule} from
    "@axis-core-1.0.0-test/modules/Auction/MockBatchAuctionModule.sol";

import {keycodeFromVeecode, toKeycode} from "@axis-core-1.0.0/modules/Keycode.sol";
import {Veecode} from "@axis-core-1.0.0/modules/Modules.sol";

import {BPOOLv1, Range, Position} from "../modules/BPOOL.v1.sol";

import {MockERC20} from "@solmate-6.7.0/test/utils/mocks/MockERC20.sol";
import {FixedPointMathLib} from "@solmate-6.7.0/utils/FixedPointMathLib.sol";

abstract contract BaselineDTLHandler is BeforeAfter, Assertions {
    /*//////////////////////////////////////////////////////////////////////////
                                HANDLER VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    uint256 internal lotCapacity;

    uint256 internal baselineCuratorFee_;

    BaselineAxisLaunch.CreateData internal _createData;

    address internal sellerBaseline_;

    int24 internal _ANCHOR_TICK_WIDTH;
    int24 internal _DISCOVERY_TICK_WIDTH;
    uint24 internal _FLOOR_RESERVES_PERCENT;
    int24 internal _FLOOR_RANGE_GAP;
    int24 internal _ANCHOR_TICK_U;
    uint24 internal _POOL_PERCENT;

    /*//////////////////////////////////////////////////////////////////////////
                                TARGET FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function baselineDTL_createLot(uint256 sellerIndexSeed) public {
        // PRE-CONDITIONS
        sellerBaseline_ = randomAddress(sellerIndexSeed);

        lotCapacity = 10 ether;

        _ANCHOR_TICK_WIDTH = int24(int256(bound(uint256(int256(_ANCHOR_TICK_WIDTH)), 10, 50)));
        _DISCOVERY_TICK_WIDTH = int24(int256(bound(uint256(int256(_DISCOVERY_TICK_WIDTH)), 1, 500)));
        _FLOOR_RESERVES_PERCENT = uint24(bound(uint256(_FLOOR_RESERVES_PERCENT), 10e2, 90e2));
        _FLOOR_RANGE_GAP = int24(int256(bound(uint256(int256(_FLOOR_RANGE_GAP)), 0, 500)));
        _ANCHOR_TICK_U = _baselineToken.getActiveTS();
        _POOL_PERCENT = 100e2;

        if (_dtlBaseline.lotId() != type(uint96).max) return;

        _createData = BaselineAxisLaunch.CreateData({
            recipient: sellerBaseline_,
            poolPercent: _POOL_PERCENT,
            floorReservesPercent: _FLOOR_RESERVES_PERCENT,
            floorRangeGap: _FLOOR_RANGE_GAP,
            anchorTickU: _ANCHOR_TICK_U,
            anchorTickWidth: _ANCHOR_TICK_WIDTH,
            allowlistParams: abi.encode("")
        });

        IAuction.AuctionParams memory auctionParams = IAuction.AuctionParams({
            start: uint48(block.timestamp),
            duration: 1 days,
            capacityInQuote: false,
            capacity: _scaleBaseTokenAmount(lotCapacity),
            implParams: abi.encode(_fpbParams)
        });

        __before(_lotId, sellerBaseline_, _dtlBaselineAddress);

        // ACTION
        vm.prank(address(_baselineAuctionHouse));
        try _fpbModule.auction(_lotId, auctionParams, _quoteTokenDecimals, _baseTokenDecimals) {}
        catch {
            assert(false);
        }

        _baselineAuctionHouse.setLotCounter(_lotId + 1);
        _baselineAuctionHouse.setAuctionReference(_lotId, _fpbModule.VEECODE());

        vm.prank(address(_baselineAuctionHouse));
        try _dtlBaseline.onCreate(
            _lotId,
            sellerBaseline_,
            address(_baselineToken),
            address(_quoteToken),
            _scaleBaseTokenAmount(lotCapacity),
            true,
            abi.encode(_createData)
        ) {
            // POST-CONDITIONS
            __after(_lotId, sellerBaseline_, _dtlBaselineAddress);

            _assertBaselineTokenBalances();
        } catch {
            assert(false);
        }
    }

    struct OnCancelBaselineTemps {
        address sender;
        uint96 lotId;
    }

    function baselineDTL_onCancel(uint256 senderIndexSeed, uint256 lotIndexSeed) public {
        // PRE-CONDTIONS
        if (_dtlBaseline.lotId() == type(uint96).max) return;
        OnCancelBaselineTemps memory d;
        d.sender = randomAddress(senderIndexSeed);

        __before(_lotId, sellerBaseline_, _dtlBaselineAddress);

        vm.prank(address(_baselineAuctionHouse));
        _baselineToken.transfer(_dtlBaselineAddress, lotCapacity);

        // ACTION
        vm.prank(address(_baselineAuctionHouse));
        try _dtlBaseline.onCancel(_lotId, _scaleBaseTokenAmount(lotCapacity), true, abi.encode(""))
        {
            // POST-CONDITIONS
            __after(_lotId, sellerBaseline_, _dtlBaselineAddress);

            equal(
                _after.baselineTotalSupply,
                0 + baselineCuratorFee_,
                "AX-36: Baseline token total supply after _onCancel should equal 0"
            );

            equal(
                _dtlBaseline.auctionComplete(),
                true,
                "AX-37: BaselineDTL_onCancel should mark auction completed"
            );

            equal(
                _after.dtlBaselineBalance,
                _before.dtlBaselineBalance,
                "AX-38: When calling BaselineDTL_onCancel DTL base token balance should equal 0"
            );

            equal(
                _baselineToken.balanceOf(address(_baselineToken)),
                0,
                "AX-39: When calling BaselineDTL_onCancel baseline contract base token balance should equal 0"
            );
        } catch (bytes memory err) {
            bytes4[3] memory errors = [
                BaselineAxisLaunch.Callback_MissingFunds.selector,
                BaselineAxisLaunch.Callback_AlreadyComplete.selector,
                BaseCallback.Callback_InvalidParams.selector
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

    struct OnCurateBaselineTemps {
        address sender;
        uint96 lotId;
    }

    function baselineDTL_onCurate(
        uint256 senderIndexSeed,
        uint256 lotIndexSeed,
        uint256 curatorFee_
    ) public {
        // PRE-CONDTIONS
        if (_dtlBaseline.lotId() == type(uint96).max) return;
        OnCurateBaselineTemps memory d;
        d.sender = randomAddress(senderIndexSeed);

        __before(_lotId, sellerBaseline_, _dtlBaselineAddress);

        curatorFee_ = bound(curatorFee_, 0, 5e18);
        // curatorFee_ = 0;

        // ACTION
        vm.prank(address(_baselineAuctionHouse));
        try _dtlBaseline.onCurate(_lotId, curatorFee_, true, abi.encode("")) {
            // POST-CONDITIONS
            __after(_lotId, sellerBaseline_, _dtlBaselineAddress);

            equal(
                _after.auctionHouseBaselineBalance,
                _before.auctionHouseBaselineBalance + curatorFee_,
                "AX-40: BaselineDTL_onCurate should credit auction house correct base token fees"
            );

            baselineCuratorFee_ += curatorFee_;
        } catch (bytes memory err) {
            bytes4[3] memory errors = [
                BaselineAxisLaunch.Callback_MissingFunds.selector,
                BaselineAxisLaunch.Callback_AlreadyComplete.selector,
                BaseCallback.Callback_InvalidParams.selector
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

    struct OnSettleBaselineTemps {
        address sender;
        uint96 lotId;
    }

    function baselineDTL_onSettle(
        uint256 senderIndexSeed,
        uint256 lotIndexSeed,
        uint256 proceeds_,
        uint256 refund_
    ) public {
        // PRE-CONDTIONS
        if (_dtlBaseline.lotId() == type(uint96).max) return;
        refund_ = ((lotCapacity * 4e2) / 100e2);
        uint256 proceeds = lotCapacity - refund_;

        OnSettleBaselineTemps memory d;
        d.sender = randomAddress(senderIndexSeed);

        __before(_lotId, sellerBaseline_, _dtlBaselineAddress);

        givenAddressHasQuoteTokenBalance(_dtlBaselineAddress, _PROCEEDS_AMOUNT);
        _transferBaselineTokenRefund(_REFUND_AMOUNT);

        // ACTION
        vm.prank(address(_baselineAuctionHouse));
        try _dtlBaseline.onSettle(
            _lotId, _PROCEEDS_AMOUNT, _scaleBaseTokenAmount(_REFUND_AMOUNT), abi.encode("")
        ) {
            // POST-CONDITIONS
            __after(_lotId, sellerBaseline_, _dtlBaselineAddress);

            _assertQuoteTokenBalances();
            _assertBaseTokenBalances();
            _assertCirculatingSupply();
            _assertAuctionComplete();
            _assertPoolReserves();
        } catch (bytes memory err) {
            bytes4[3] memory errors = [
                BaselineAxisLaunch.Callback_MissingFunds.selector,
                BaselineAxisLaunch.Callback_AlreadyComplete.selector,
                BaseCallback.Callback_InvalidParams.selector
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

    function _scaleBaseTokenAmount(uint256 amount_) internal view returns (uint256) {
        return FixedPointMathLib.mulDivDown(amount_, 10 ** _baseTokenDecimals, _BASE_SCALE);
    }

    function _getRangeBAssets(Range range_) internal returns (uint256) {
        Position memory position = _baselineToken.getPosition(range_);

        return position.bAssets;
    }

    function _getRangeReserves(Range range_) internal returns (uint256) {
        Position memory position = _baselineToken.getPosition(range_);

        return position.reserves;
    }

    function _assertBaselineTokenBalances() internal {
        equal(
            _after.sellerBaselineBalance,
            _before.sellerBaselineBalance,
            "AX-09: DTL Callbacks should not change seller base token balance"
        );
        equal(
            _after.dtlBaselineBalance,
            _before.dtlBaselineBalance,
            "AX-10: DTL Callbacks should not change dtl base token balance"
        );
        equal(
            _after.auctionHouseBaselineBalance,
            _scaleBaseTokenAmount(lotCapacity),
            "AX-32: When calling BaselineDTL_createLot auction house base token balance should be equal to lot Capacity lotId"
        );
    }

    function _assertQuoteTokenBalances() internal {
        equal(
            _quoteToken.balanceOf(_dtlBaselineAddress),
            0,
            "AX-17: After DTL_onSettle DTL Address quote token balance should equal 0"
        );
        equal(
            _quoteToken.balanceOf(address(_quoteToken)),
            0,
            "AX-33: After DTL_onSettle quote token balance of quote token should equal 0"
        );
        uint256 poolProceeds = _PROCEEDS_AMOUNT * _createData.poolPercent / 100e2;
        equal(
            _quoteToken.balanceOf(address(_baselineToken.pool())),
            poolProceeds,
            "AX-34: BaselineDTL_onSettle should credit baseline pool with correct quote token proceeds"
        );
        equal(
            _quoteToken.balanceOf(sellerBaseline_),
            _quoteToken.balanceOf(sellerBaseline_) + _PROCEEDS_AMOUNT - poolProceeds,
            "AX-35: BaselineDTL_onSettle should credit seller quote token proceeds"
        );
    }

    function _assertBaseTokenBalances() internal {
        equal(
            _baselineToken.balanceOf(_dtlBaselineAddress),
            0,
            "AX-18: After DTL_onSettle DTL Address base token balance should equal 0"
        );
        equal(
            _baselineToken.balanceOf(address(_baselineToken)),
            0,
            "AX-41: After BaselineDTL_onSettle baseline token base token balance should equal 0"
        );

        uint256 totalSupply = _baselineToken.totalSupply();

        // No payout distributed to "bidders", so don't account for it here
        uint256 spotSupply = totalSupply - _baselineToken.getPosition(Range.FLOOR).bAssets
            - _baselineToken.getPosition(Range.ANCHOR).bAssets
            - _baselineToken.getPosition(Range.DISCOVERY).bAssets;

        uint256 poolSupply = totalSupply - spotSupply;

        assertApproxEq(
            _baselineToken.balanceOf(address(_baselineToken.pool())),
            poolSupply,
            2,
            "AX-42: After BaselineDTL_onSettle baseline pool base token balance should equal baseline pool supply"
        );
        equal(
            _baselineToken.balanceOf(sellerBaseline_),
            0,
            "AX-43: After BaselineDTL_onSettle seller baseline token balance should equal 0"
        );
    }

    function _assertCirculatingSupply() internal {
        uint256 totalSupply = _baselineToken.totalSupply();

        assertApproxEq(
            totalSupply - _baselineToken.getPosition(Range.FLOOR).bAssets
                - _baselineToken.getPosition(Range.ANCHOR).bAssets
                - _baselineToken.getPosition(Range.DISCOVERY).bAssets - _credt.totalCreditIssued(), // totalCreditIssued would affect supply, totalCollateralized will not
            lotCapacity - _REFUND_AMOUNT + baselineCuratorFee_,
            2, // There is a difference (rounding error?) of 2
            "AX-44: circulating supply should equal lot capacity plus curatorFee minus refund"
        );
    }

    function _assertAuctionComplete() internal {
        equal(
            _dtlBaseline.auctionComplete(),
            true,
            "AX-45: BaselineDTL_onSettle should mark auction complete"
        );
    }

    function _assertPoolReserves() internal {
        uint256 poolProceeds = _PROCEEDS_AMOUNT * _createData.poolPercent / 100e2;
        uint256 floorProceeds = poolProceeds * _createData.floorReservesPercent / 100e2;
        assertApproxEq(
            _getRangeReserves(Range.FLOOR),
            floorProceeds,
            1, // There is a difference (rounding error?) of 1
            "AX-46: After BaselineDTL_onSettle floor reserves should equal floor proceeds"
        );
        assertApproxEq(
            _getRangeReserves(Range.ANCHOR),
            poolProceeds - floorProceeds,
            1, // There is a difference (rounding error?) of 1
            "AX-47: After BaselineDTL_onSettle anchor reserves should equal pool proceeds - floor proceeds"
        );
        equal(
            _getRangeReserves(Range.DISCOVERY),
            0,
            "AX-48: After BaselineDTL_onSettle discovery reserves should equal 0"
        );

        // BAssets deployed into the pool
        equal(
            _getRangeBAssets(Range.FLOOR),
            0,
            "AX-49: After BaselineDTL_onSettle floor bAssets should equal 0"
        );
        gt(
            _getRangeBAssets(Range.ANCHOR),
            0,
            "AX-50: After BaselineDTL_onSettle anchor bAssets should be greater than 0"
        );
        gt(
            _getRangeBAssets(Range.DISCOVERY),
            0,
            "AX-51: After BaselineDTL_onSettle discovery bAssets should be greater than 0"
        );
    }
}
