// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";

import {Kernel, Module, Keycode, toKeycode} from "@baseline/Kernel.sol";
import {TimeslotLib} from "./utils/TimeslotLib.sol";

/// @notice Individual credit account information per user
struct CreditAccount {
    uint256 credit; // Used to keep track of data in timeslots
    uint256 collateral; // bAsset collateral
    uint256 expiry; // Date when credit expires and collateral is defaulted
}

/// @notice Credit Module
contract CREDTv1 is Module {
    using TimeslotLib for uint256;

    // --- STATE ---------------------------------------------------

    /// @notice bAsset token
    ERC20 public bAsset;

    /// @notice Individual credit account state
    mapping(address => CreditAccount) internal creditAccounts;

    /// @notice Container for aggregate credit and collateral to be defaulted at a timeslot
    struct Defaultable {
        uint256 credit; // Total reserves issued for this timeslot
        uint256 collateral; // Total bAssets collateralized for this timeslot
    }

    // List of aggregate credits and collateral that must be defaulted
    // when a timeslot is reached
    mapping(uint256 => Defaultable) public defaultList;

    /// @notice Last timeslot that was defaulted, acts as queue iterator
    uint256 public lastDefaultedTimeslot;

    /// @notice Total reserves issued as credit
    uint256 public totalCreditIssued;

    /// @notice Total bAssets collateralized
    uint256 public totalCollateralized;

    // Events

    event DefaultSelf(address user_, uint256 credit_, uint256 collateral_);
    event Defaulted(uint256 timeslot_, uint256 credit_, uint256 collateral_);

    // Errors

    error NoAccountAvailable();
    error InvalidExpiry();
    error InvalidCreditAccount();

    // --- INITIALIZATION --------------------------------------------

    constructor(Kernel _kernel) Module(_kernel) {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("CREDT");
    }

    /// @inheritdoc Module
    function VERSION() public pure override returns (uint8 major_, uint8 minor_) {
        major_ = 1;
        minor_ = 0;
    }

    /// @inheritdoc Module
    function INIT() external override onlyKernel {
        lastDefaultedTimeslot = TimeslotLib.today();

        // Set BPOOL as bAsset
        bAsset = ERC20(address(kernel.getModuleForKeycode(toKeycode("BPOOL"))));
    }

    function setTotalCreditIssues(uint256 totalCreditIssued_) external {
        totalCreditIssued = totalCreditIssued_;
    }

    function setTotalCollateralized(uint256 totalCollateralized_) external {
        totalCollateralized = totalCollateralized_;
    }

    function totalInterestAccumulated() external view returns (uint256) {}

    function getCreditAccount(address _user)
        external
        view
        returns (CreditAccount memory account_)
    {}

    function updateCreditAccount(
        address _user,
        uint256 _newCollateral,
        uint256 _newCredit,
        uint256 _newExpiry
    ) external {}
}
