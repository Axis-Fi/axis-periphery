// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Setup} from "../Setup.sol";

import {Veecode} from "@axis-core-1.0.0/modules/Keycode.sol";
import {ICallback} from "@axis-core-1.0.0/interfaces/ICallback.sol";
import {BaseDirectToLiquidity} from "../../../src/callbacks/liquidity/BaseDTL.sol";
import {LinearVesting} from "@axis-core-1.0.0/modules/derivatives/LinearVesting.sol";

abstract contract BeforeAfter is Setup {
    struct Vars {
        address seller;
        uint256 sellerBaseBalance;
        uint256 sellerBaselineBalance;
        uint256 dtlBaseBalance;
        uint256 dtlBaselineBalance;
        uint256 auctionHouseBaseBalance;
        uint256 auctionHouseBaselineBalance;
        uint256 baselineTotalSupply;
        BaseDirectToLiquidity.DTLConfiguration dtlConfigV2;
        BaseDirectToLiquidity.DTLConfiguration dtlConfigV3;
    }

    Vars internal _before;
    Vars internal _after;

    function __before(uint96 lotId, address seller, address _dtlAddress) internal {
        _before.dtlConfigV2 = _getDTLConfigurationV2(lotId);
        _before.dtlConfigV3 = _getDTLConfigurationV3(lotId);
        (_before.seller,,,,,,,,) = _auctionHouse.lotRouting(lotId);
        _before.sellerBaseBalance = _baseToken.balanceOf(seller);
        _before.dtlBaseBalance = _baseToken.balanceOf(_dtlAddress);
        _before.auctionHouseBaseBalance = _baseToken.balanceOf(address(_auctionHouse));
        _before.sellerBaselineBalance = _baselineToken.balanceOf(seller);
        _before.dtlBaselineBalance = _baselineToken.balanceOf(_dtlAddress);
        _before.auctionHouseBaselineBalance =
            _baselineToken.balanceOf(address(_baselineAuctionHouse));
        _before.baselineTotalSupply = _baselineToken.totalSupply();
    }

    function __after(uint96 lotId, address seller, address _dtlAddress) internal {
        _after.dtlConfigV2 = _getDTLConfigurationV2(lotId);
        _after.dtlConfigV3 = _getDTLConfigurationV3(lotId);
        (_after.seller,,,,,,,,) = _auctionHouse.lotRouting(lotId);
        _after.sellerBaseBalance = _baseToken.balanceOf(seller);
        _after.dtlBaseBalance = _baseToken.balanceOf(_dtlAddress);
        _after.auctionHouseBaseBalance = _baseToken.balanceOf(address(_auctionHouse));
        _after.sellerBaselineBalance = _baselineToken.balanceOf(seller);
        _after.dtlBaselineBalance = _baselineToken.balanceOf(_dtlAddress);
        _after.auctionHouseBaselineBalance =
            _baselineToken.balanceOf(address(_baselineAuctionHouse));
        _after.baselineTotalSupply = _baselineToken.totalSupply();
    }

    function _getDTLConfigurationV2(uint96 lotId_)
        internal
        view
        returns (BaseDirectToLiquidity.DTLConfiguration memory)
    {
        (
            address recipient_,
            uint256 lotCapacity_,
            uint256 lotCuratorPayout_,
            uint24 poolPercent_,
            uint48 vestingStart_,
            uint48 vestingExpiry_,
            LinearVesting linearVestingModule_,
            bool active_,
            bytes memory implParams_
        ) = _dtlV2.lotConfiguration(lotId_);

        return BaseDirectToLiquidity.DTLConfiguration({
            recipient: recipient_,
            lotCapacity: lotCapacity_,
            lotCuratorPayout: lotCuratorPayout_,
            poolPercent: poolPercent_,
            vestingStart: vestingStart_,
            vestingExpiry: vestingExpiry_,
            linearVestingModule: linearVestingModule_,
            active: active_,
            implParams: implParams_
        });
    }

    function _getDTLConfigurationV3(uint96 lotId_)
        internal
        view
        returns (BaseDirectToLiquidity.DTLConfiguration memory)
    {
        (
            address recipient_,
            uint256 lotCapacity_,
            uint256 lotCuratorPayout_,
            uint24 poolPercent_,
            uint48 vestingStart_,
            uint48 vestingExpiry_,
            LinearVesting linearVestingModule_,
            bool active_,
            bytes memory implParams_
        ) = _dtlV3.lotConfiguration(lotId_);

        return BaseDirectToLiquidity.DTLConfiguration({
            recipient: recipient_,
            lotCapacity: lotCapacity_,
            lotCuratorPayout: lotCuratorPayout_,
            poolPercent: poolPercent_,
            vestingStart: vestingStart_,
            vestingExpiry: vestingExpiry_,
            linearVestingModule: linearVestingModule_,
            active: active_,
            implParams: implParams_
        });
    }
}
