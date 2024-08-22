// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BeforeAfter} from "../helpers/BeforeAfter.sol";
import {Assertions} from "../helpers/Assertions.sol";

import {UniswapV2DirectToLiquidity} from "../../../../../src/callbacks/liquidity/UniswapV2DTL.sol";
import {BaseDirectToLiquidity} from "../../../../../src/callbacks/liquidity/BaseDTL.sol";
import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {IUniswapV2Pair} from "@uniswap-v2-core-1.0.1/interfaces/IUniswapV2Pair.sol";
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";

import {keycodeFromVeecode, toKeycode} from "@axis-core-1.0.0/modules/Keycode.sol";
import {IAuctionHouse} from "@axis-core-1.0.0/interfaces/IAuctionHouse.sol";
import {IAuction} from "@axis-core-1.0.0/interfaces/modules/IAuction.sol";
import {ILinearVesting} from "@axis-core-1.0.0/interfaces/modules/derivatives/ILinearVesting.sol";
import {IUniswapV2Pair} from "@uniswap-v2-core-1.0.1/interfaces/IUniswapV2Pair.sol";
import {FixedPointMathLib} from "@solmate-6.7.0/utils/FixedPointMathLib.sol";
import {LinearVesting} from "@axis-core-1.0.0/modules/derivatives/LinearVesting.sol";

abstract contract UniswapV2DTLHandler is BeforeAfter, Assertions {
    /*//////////////////////////////////////////////////////////////////////////
                                HANDLER VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    uint256 internal constant _MINIMUM_LIQUIDITY = 10 ** 3;

    uint96 internal _proceeds;
    uint96 internal _refund;
    uint96 internal _capacityUtilised;
    uint96 internal _quoteTokensToDeposit;
    uint96 internal _baseTokensToDeposit;
    uint96 internal _curatorPayout;
    uint256 internal _auctionPrice;
    uint256 internal _quoteTokensDonated;

    uint24 internal _maxSlippage = 1;

    BaseDirectToLiquidity.OnCreateParams internal _dtlCreateParamsV2;
    UniswapV2DirectToLiquidity.UniswapV2OnCreateParams internal _uniswapV2CreateParams;

    mapping(uint96 => bool) internal isLotFinished;

    mapping(uint96 => BaseDirectToLiquidity.OnCreateParams) internal lotIdCreationParams;

    /*//////////////////////////////////////////////////////////////////////////
                                TARGET FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function uniswapV2DTL_createLot(
        uint256 sellerIndexSeed,
        uint24 poolPercent,
        uint48 vestingStart,
        uint48 vestingExpiry
    ) public {
        // PRE-CONDITIONS
        if (lotIdsV2.length == 1) return;
        address seller_ = randomAddress(sellerIndexSeed);
        __before(0, seller_, _dtlV2Address);

        poolPercent = uint24(bound(uint256(poolPercent), 10e2, 100e2));
        vestingStart = uint48(
            bound(
                uint256(vestingStart), uint48(block.timestamp) + 2 days, uint256(type(uint48).max)
            )
        );
        vestingExpiry = uint48(
            bound(uint256(vestingStart), uint256(vestingStart + 1), uint256(type(uint48).max))
        );
        _maxSlippage = uint24(bound(uint256(_maxSlippage), 1, 100e2));

        if (vestingStart == vestingExpiry) return;

        _uniswapV2CreateParams =
            UniswapV2DirectToLiquidity.UniswapV2OnCreateParams({maxSlippage: _maxSlippage});

        _dtlCreateParamsV2 = BaseDirectToLiquidity.OnCreateParams({
            poolPercent: 100e2, //poolPercent,
            vestingStart: vestingStart,
            vestingExpiry: vestingExpiry,
            recipient: seller_,
            implParams: abi.encode(_uniswapV2CreateParams)
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
            callbacks: _dtlV2,
            callbackData: abi.encode(_dtlCreateParamsV2),
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
                _after.dtlConfigV2.recipient,
                seller_,
                "AX-01: UniswapV2Dtl_onCreate() should set DTL Config recipient"
            );
            equal(
                _after.dtlConfigV2.lotCapacity,
                _LOT_CAPACITY,
                "AX-02: UniswapV2Dtl_onCreate() should set DTL Config lotCapacity"
            );
            equal(
                _after.dtlConfigV2.lotCuratorPayout,
                0,
                "AX-03: UniswapV2Dtl_onCreate() should set DTL Config lotCuratorPayout"
            );
            equal(
                _after.dtlConfigV2.poolPercent,
                _dtlCreateParamsV2.poolPercent,
                "AX-04: UniswapV2Dtl_onCreate() should set DTL Config poolPercent"
            );
            equal(
                _after.dtlConfigV2.vestingStart,
                vestingStart,
                "AX-05: UniswapV2Dtl_onCreate() should set DTL Config vestingStart"
            );
            equal(
                _after.dtlConfigV2.vestingExpiry,
                vestingExpiry,
                "AX-06: UniswapV2Dtl_onCreate() should set DTL Config vestingExpiry"
            );
            equal(
                address(_after.dtlConfigV2.linearVestingModule),
                vestingStart == 0 ? address(0) : address(_linearVesting),
                "AX-07: UniswapV2Dtl_onCreate() should set DTL Config linearVestingModule"
            );
            equal(
                _after.dtlConfigV2.active,
                true,
                "AX-08: UniswapV2Dtl_onCreate() should set DTL Config active"
            );

            // Assert balances
            _assertBaseTokenBalancesV2();

            lotIdsV2.push(lotIdCreated);
            lotIdCreationParams[lotIdCreated] = _dtlCreateParamsV2;
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

    struct OnCancelTemps {
        address seller;
        address sender;
        uint96 lotId;
    }

    function uniswapV2DTL_onCancel(uint256 senderIndexSeed, uint256 lotIndexSeed) public {
        // PRE-CONDITIONS
        OnCancelTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.lotId = randomLotIdV2(lotIndexSeed);
        (d.seller,,,,,,,,) = _auctionHouse.lotRouting(d.lotId);

        __before(d.lotId, d.seller, _dtlV2Address);
        if (_before.seller == address(0)) return;

        // ACTION
        vm.prank(address(_auctionHouse));
        try _dtlV2.onCancel(d.lotId, _REFUND_AMOUNT, false, abi.encode("")) {
            // POST-CONDITIONS
            __after(d.lotId, d.seller, _dtlV2Address);

            equal(
                _after.dtlConfigV2.active,
                false,
                "AX-11: DTL_onCancel() should set DTL Config active to false"
            );

            _assertBaseTokenBalancesV2();

            isLotFinished[d.lotId] = true;
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

    struct OnCurateTemps {
        address seller;
        address sender;
        uint96 lotId;
    }

    function uniswapV2DTL_onCurate(uint256 senderIndexSeed, uint256 lotIndexSeed) public {
        // PRE-CONDITIONS
        OnCurateTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.lotId = randomLotIdV2(lotIndexSeed);
        (d.seller,,,,,,,,) = _auctionHouse.lotRouting(d.lotId);

        __before(d.lotId, d.seller, _dtlV2Address);
        if (_before.seller == address(0)) return;

        // ACTION
        vm.prank(address(_auctionHouse));
        try _dtlV2.onCurate(d.lotId, _PAYOUT_AMOUNT, false, abi.encode("")) {
            // POST-CONDITIONS
            __after(d.lotId, d.seller, _dtlV2Address);

            equal(
                _after.dtlConfigV2.lotCuratorPayout,
                _PAYOUT_AMOUNT,
                "AX-12: DTL_onCurate should set DTL Config lotCuratorPayout"
            );

            equal(
                _after.auctionHouseBaseBalance,
                (_LOT_CAPACITY * lotIdsV2.length) + (_LOT_CAPACITY * lotIdsV3.length),
                "AX-13: When calling DTL_onCurate auction house base token balance should be equal to lot Capacity of each lotId"
            );

            _assertBaseTokenBalancesV2();

            _curatorPayout = _PAYOUT_AMOUNT;
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

    struct OnSettleTemps {
        address seller;
        address sender;
        uint96 lotId;
    }

    function uniswapV2DTL_onSettle(
        uint256 senderIndexSeed,
        uint256 lotIndexSeed,
        uint96 proceeds_,
        uint96 refund
    ) public {
        // PRE-CONDITIONS
        proceeds_ = uint96(bound(uint256(proceeds_), 2e18, 10e18));
        refund = uint96(bound(uint256(refund), 0, 1e18));

        address pairAddress = _uniV2Factory.getPair(address(_baseToken), address(_quoteToken));
        if (pairAddress == address(0)) {
            _createPool();
        }

        OnSettleTemps memory d;
        d.sender = randomAddress(senderIndexSeed);
        d.lotId = randomLotIdV2(lotIndexSeed);
        (d.seller,,,,,,,,) = _auctionHouse.lotRouting(d.lotId);

        setV2CallbackParameters(d.lotId, proceeds_, refund);

        __before(d.lotId, d.seller, _dtlV2Address);
        if (_before.seller == address(0)) return;
        if (isLotFinished[d.lotId] == true) return;

        givenAddressHasQuoteTokenBalance(_dtlV2Address, _quoteTokensToDeposit);
        givenAddressHasBaseTokenBalance(_before.seller, _baseTokensToDeposit);
        givenAddressHasBaseTokenAllowance(_before.seller, _dtlV2Address, _baseTokensToDeposit);

        // ACTION
        vm.prank(address(_auctionHouse));
        try _dtlV2.onSettle(d.lotId, _proceeds, _refund, abi.encode("")) {
            // POST-CONDITIONS
            __after(d.lotId, d.seller, _dtlV2Address);

            _assertLpTokenBalance(d.lotId, d.seller);
            if (_before.dtlConfigV2.vestingStart != 0) {
                _assertVestingTokenBalance(d.lotId, d.seller);
            }
            _assertQuoteTokenBalance();
            _assertBaseTokenBalance();
            _assertApprovals();

            isLotFinished[d.lotId] = true;
        } catch (bytes memory err) {
            bytes4[1] memory errors = [BaseDirectToLiquidity.Callback_InsufficientBalance.selector];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            assert(expected);
            return;
        } catch Error(string memory reason) {
            string[3] memory stringErrors = [
                "UniswapV2Library: INSUFFICIENT_LIQUIDITY",
                "UniswapV2Router: INSUFFICIENT_A_AMOUNT",
                "UniswapV2Router: INSUFFICIENT_B_AMOUNT"
            ];
            for (uint256 i = 0; i < stringErrors.length; i++) {
                if (compareStrings(stringErrors[i], reason)) {
                    t(
                        false,
                        "AX-52: UniswapV2DTL_onSettle should not fail with 'UniswapV2Library: INSUFFICIENT_LIQUIDITY'"
                    );
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _createPool() internal returns (address) {
        return _uniV2Factory.createPair(address(_quoteToken), address(_baseToken));
    }

    function _getUniswapV2Pool() internal view returns (IUniswapV2Pair) {
        return IUniswapV2Pair(_uniV2Factory.getPair(address(_quoteToken), address(_baseToken)));
    }

    function setV2CallbackParameters(uint96 lotId, uint96 proceeds_, uint96 refund_) internal {
        _proceeds = proceeds_;
        _refund = refund_;

        // Calculate the capacity utilised
        // Any unspent curator payout is included in the refund
        // However, curator payouts are linear to the capacity utilised
        // Calculate the percent utilisation
        uint96 capacityUtilisationPercent = 100e2
            - uint96(FixedPointMathLib.mulDivDown(_refund, 100e2, _LOT_CAPACITY + _curatorPayout));
        _capacityUtilised = _LOT_CAPACITY * capacityUtilisationPercent / 100e2;

        // The proceeds utilisation percent scales the quote tokens and base tokens linearly
        _quoteTokensToDeposit = _proceeds * lotIdCreationParams[lotId].poolPercent / 100e2;
        _baseTokensToDeposit = _capacityUtilised * lotIdCreationParams[lotId].poolPercent / 100e2;

        _auctionPrice = _proceeds * 10 ** _baseToken.decimals() / (_LOT_CAPACITY - _refund);
    }

    function _assertBaseTokenBalancesV2() internal {
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

    function _assertLpTokenBalance(uint96 lotId, address seller) internal {
        // Get the pools deployed by the DTL callback
        IUniswapV2Pair pool = _getUniswapV2Pool();

        // Exclude the LP token balance on this contract
        uint256 testBalance = pool.balanceOf(address(this));

        uint256 sellerExpectedBalance;
        uint256 linearVestingExpectedBalance;
        // Only has a balance if not vesting
        if (lotIdCreationParams[lotId].vestingStart == 0) {
            sellerExpectedBalance = pool.totalSupply() - testBalance - _MINIMUM_LIQUIDITY;
        } else {
            linearVestingExpectedBalance = pool.totalSupply() - testBalance - _MINIMUM_LIQUIDITY;
        }

        equal(
            pool.balanceOf(seller),
            lotIdCreationParams[lotId].recipient == seller ? sellerExpectedBalance : 0,
            "AX-14: DTL_onSettle should should credit seller the expected LP token balance"
        );
        equal(
            pool.balanceOf(address(_linearVesting)),
            linearVestingExpectedBalance,
            "AX-15: DTL_onSettle should should credit linearVestingModule the expected LP token balance"
        );
    }

    function _assertVestingTokenBalance(uint96 lotId, address seller) internal {
        // Exit if not vesting
        if (lotIdCreationParams[lotId].vestingStart == 0) {
            return;
        }

        // Get the pools deployed by the DTL callback
        address pool = address(_getUniswapV2Pool());

        // Get the wrapped address
        (, address wrappedVestingTokenAddress) = _linearVesting.deploy(
            pool,
            abi.encode(
                ILinearVesting.VestingParams({
                    start: lotIdCreationParams[lotId].vestingStart,
                    expiry: lotIdCreationParams[lotId].vestingExpiry
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

    function _assertQuoteTokenBalance() internal {
        equal(
            _quoteToken.balanceOf(_dtlV2Address),
            0,
            "AX-17: After DTL_onSettle DTL Address quote token balance should equal 0"
        );
    }

    function _assertBaseTokenBalance() internal {
        equal(
            _baseToken.balanceOf(_dtlV2Address),
            0,
            "AX-18: After DTL_onSettle DTL Address base token balance should equal 0"
        );
    }

    function _assertApprovals() internal {
        // Ensure there are no dangling approvals
        equal(
            _quoteToken.allowance(_dtlV2Address, address(_uniV2Router)),
            0,
            "AX-19: After UniswapV2DTL_onSettle DTL Address quote token allowance for the UniswapV2 Router should equal 0"
        );
        equal(
            _baseToken.allowance(_dtlV2Address, address(_uniV2Router)),
            0,
            "AX-20: After UniswapV2DTL_onSettle DTL Address base token allowance for the UniswapV2 Router should equal 0"
        );
    }
}
