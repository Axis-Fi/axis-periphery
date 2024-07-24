// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";

import {
    ICREDTv1,
    CreditAccount
} from "../../../../../src/callbacks/liquidity/BaselineV2/lib/ICREDT.sol";

contract MockCREDT is ICREDTv1 {
    uint256 internal _totalCreditIssued;
    uint256 internal _totalCollateralized;

    function bAsset() external view override returns (ERC20) {}

    function creditAccounts(address)
        external
        view
        override
        returns (uint256 credit, uint256 collateral, uint256 expiry)
    {}

    function defaultList(uint256)
        external
        view
        override
        returns (uint256 credit, uint256 collateral)
    {}

    function lastDefaultedTimeslot() external view override returns (uint256) {}

    function totalCreditIssued() external view override returns (uint256) {}

    function setTotalCreditIssues(uint256 totalCreditIssued_) external {
        _totalCreditIssued = totalCreditIssued_;
    }

    function totalCollateralized() external view override returns (uint256) {}

    function setTotalCollateralized(uint256 totalCollateralized_) external {
        _totalCollateralized = totalCollateralized_;
    }

    function totalInterestAccumulated() external view override returns (uint256) {}

    function getCreditAccount(address _user)
        external
        view
        override
        returns (CreditAccount memory account_)
    {}

    function updateCreditAccount(
        address _user,
        uint256 _newCollateral,
        uint256 _newCredit,
        uint256 _newExpiry
    ) external override {}
}
