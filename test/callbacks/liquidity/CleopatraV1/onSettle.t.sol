// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {CleopatraV1DirectToLiquidityTest} from "./CleopatraV1DTLTest.sol";

// Libraries
import {FixedPointMathLib} from "@solmate-6.7.0/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";

// Cleopatra
import {ICleopatraV1Pool} from
    "../../../../src/callbacks/liquidity/Cleopatra/lib/ICleopatraV1Pool.sol";

// AuctionHouse
import {ILinearVesting} from "@axis-core-1.0.0/interfaces/modules/derivatives/ILinearVesting.sol";
import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";
import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";

contract CleopatraV1OnSettleForkTest is CleopatraV1DirectToLiquidityTest {
    uint96 internal constant _PROCEEDS = 20e18;
    uint96 internal constant _REFUND = 0;

    /// @dev The minimum amount of liquidity retained in the pool
    uint256 internal constant _MINIMUM_LIQUIDITY = 10 ** 3;

    uint96 internal _capacityUtilised;
    uint96 internal _quoteTokensToDeposit;
    uint96 internal _baseTokensToDeposit;
    uint96 internal _curatorPayout;

    uint24 internal _maxSlippage = 1; // 0.01%

    // ========== Internal functions ========== //

    function _getCleopatraV1Pool(bool stable_) internal view returns (ICleopatraV1Pool) {
        return
            ICleopatraV1Pool(_factory.getPair(address(_quoteToken), address(_baseToken), stable_));
    }

    function _getCleopatraV1Pool() internal view returns (ICleopatraV1Pool) {
        return _getCleopatraV1Pool(_cleopatraCreateParams.stable);
    }

    function _getVestingTokenId() internal view returns (uint256) {
        // Get the pools deployed by the DTL callback
        address pool = address(_getCleopatraV1Pool());

        return _linearVesting.computeId(
            pool,
            abi.encode(
                ILinearVesting.VestingParams({
                    start: _dtlCreateParams.vestingStart,
                    expiry: _dtlCreateParams.vestingExpiry
                })
            )
        );
    }

    // ========== Assertions ========== //

    function _assertLpTokenBalance() internal view {
        // Get the pools deployed by the DTL callback
        ICleopatraV1Pool pool = _getCleopatraV1Pool();

        // Exclude the LP token balance on this contract
        uint256 testBalance = pool.balanceOf(address(this));

        uint256 sellerExpectedBalance;
        uint256 linearVestingExpectedBalance;
        // Only has a balance if not vesting
        if (_dtlCreateParams.vestingStart == 0) {
            sellerExpectedBalance = pool.totalSupply() - testBalance - _MINIMUM_LIQUIDITY;
        } else {
            linearVestingExpectedBalance = pool.totalSupply() - testBalance - _MINIMUM_LIQUIDITY;
        }

        assertEq(
            pool.balanceOf(_SELLER),
            _dtlCreateParams.recipient == _SELLER ? sellerExpectedBalance : 0,
            "seller: LP token balance"
        );
        assertEq(
            pool.balanceOf(_NOT_SELLER),
            _dtlCreateParams.recipient == _NOT_SELLER ? sellerExpectedBalance : 0,
            "not seller: LP token balance"
        );
        assertEq(
            pool.balanceOf(address(_linearVesting)),
            linearVestingExpectedBalance,
            "linear vesting: LP token balance"
        );
    }

    function _assertVestingTokenBalance() internal {
        // Exit if not vesting
        if (_dtlCreateParams.vestingStart == 0) {
            return;
        }

        // Get the pools deployed by the DTL callback
        address pool = address(_getCleopatraV1Pool());

        // Get the wrapped address
        (, address wrappedVestingTokenAddress) = _linearVesting.deploy(
            pool,
            abi.encode(
                ILinearVesting.VestingParams({
                    start: _dtlCreateParams.vestingStart,
                    expiry: _dtlCreateParams.vestingExpiry
                })
            ),
            true
        );
        ERC20 wrappedVestingToken = ERC20(wrappedVestingTokenAddress);
        uint256 sellerExpectedBalance = wrappedVestingToken.totalSupply();

        assertEq(
            wrappedVestingToken.balanceOf(_SELLER),
            _dtlCreateParams.recipient == _SELLER ? sellerExpectedBalance : 0,
            "seller: vesting token balance"
        );
        assertEq(
            wrappedVestingToken.balanceOf(_NOT_SELLER),
            _dtlCreateParams.recipient == _NOT_SELLER ? sellerExpectedBalance : 0,
            "not seller: vesting token balance"
        );
    }

    function _assertQuoteTokenBalance() internal view {
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "DTL: quote token balance");
    }

    function _assertBaseTokenBalance() internal view {
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "DTL: base token balance");
    }

    // ========== Modifiers ========== //

    function _createPool() internal returns (address) {
        return _factory.createPair(
            address(_quoteToken), address(_baseToken), _cleopatraCreateParams.stable
        );
    }

    modifier givenPoolIsCreated() {
        _createPool();
        _;
    }

    modifier setCallbackParameters(uint96 proceeds_, uint96 refund_) {
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
        _quoteTokensToDeposit = _proceeds * _dtlCreateParams.proceedsUtilisationPercent / 100e2;
        _baseTokensToDeposit =
            _capacityUtilised * _dtlCreateParams.proceedsUtilisationPercent / 100e2;
        _;
    }

    modifier givenUnboundedProceedsUtilisationPercent(uint24 percent_) {
        // Bound the percent
        uint24 percent = uint24(bound(percent_, 1, 100e2));

        // Set the value on the DTL
        _dtlCreateParams.proceedsUtilisationPercent = percent;
        _;
    }

    modifier givenUnboundedOnCurate(uint96 curationPayout_) {
        // Bound the value
        _curatorPayout = uint96(bound(curationPayout_, 1e17, _LOT_CAPACITY));

        // Call the onCurate callback
        _performOnCurate(_curatorPayout);
        _;
    }

    modifier whenRefundIsBounded(uint96 refund_) {
        // Bound the refund
        _refund = uint96(bound(refund_, 1e17, 5e18));
        _;
    }

    modifier givenPoolHasDepositLowerPrice() {
        uint256 quoteTokensToDeposit = _quoteTokensToDeposit * 105 / 100;
        uint256 baseTokensToDeposit = _baseTokensToDeposit;

        // Mint additional tokens
        _quoteToken.mint(address(this), quoteTokensToDeposit);
        _baseToken.mint(address(this), baseTokensToDeposit);

        // Approve spending
        _quoteToken.approve(address(_router), quoteTokensToDeposit);
        _baseToken.approve(address(_router), baseTokensToDeposit);

        // Deposit tokens into the pool
        _router.addLiquidity(
            address(_quoteToken),
            address(_baseToken),
            _cleopatraCreateParams.stable,
            quoteTokensToDeposit,
            baseTokensToDeposit,
            quoteTokensToDeposit,
            baseTokensToDeposit,
            address(this),
            block.timestamp
        );
        _;
    }

    modifier givenPoolHasDepositHigherPrice() {
        uint256 quoteTokensToDeposit = _quoteTokensToDeposit * 95 / 100;
        uint256 baseTokensToDeposit = _baseTokensToDeposit;

        // Mint additional tokens
        _quoteToken.mint(address(this), quoteTokensToDeposit);
        _baseToken.mint(address(this), baseTokensToDeposit);

        // Approve spending
        _quoteToken.approve(address(_router), quoteTokensToDeposit);
        _baseToken.approve(address(_router), baseTokensToDeposit);

        // Deposit tokens into the pool
        _router.addLiquidity(
            address(_quoteToken),
            address(_baseToken),
            _cleopatraCreateParams.stable,
            quoteTokensToDeposit,
            baseTokensToDeposit,
            quoteTokensToDeposit,
            baseTokensToDeposit,
            address(this),
            block.timestamp
        );
        _;
    }

    // ========== Tests ========== //

    // [X] given the onSettle callback has already been called
    //  [X] when onSettle is called
    //   [X] it reverts
    //  [X] when onCancel is called
    //   [X] it reverts
    //  [X] when onCreate is called
    //   [X] it reverts
    //  [X] when onCurate is called
    //   [X] it reverts
    // [X] given the pool is created
    //  [X] it initializes the pool
    // [X] given the pool is created and initialized
    //  [X] it succeeds
    // [X] given the proceeds utilisation percent is set
    //  [X] it calculates the deposit amount correctly
    // [X] given curation is enabled
    //  [X] the utilisation percent considers this
    // [X] when the refund amount changes
    //  [X] the utilisation percent considers this
    // [X] given minting pool tokens utilises less than the available amount of base tokens
    //  [X] the excess base tokens are returned
    // [X] given minting pool tokens utilises less than the available amount of quote tokens
    //  [X] the excess quote tokens are returned
    // [X] given the send base tokens flag is false
    //  [X] it transfers the base tokens from the seller
    // [X] given vesting is enabled
    //  [X] given the recipient is not the seller
    //   [X] it mints the vesting tokens to the seller
    //  [X] it mints the vesting tokens to the seller
    // [X] given the recipient is not the seller
    //  [X] it mints the LP token to the recipient
    // [X] when multiple lots are created
    //  [X] it performs actions on the correct pool
    // [X] given the stable parameter is true
    //  [X] it creates a stable pool
    // [X] given the stable parameter is false
    //  [X] it creates a volatile pool
    // [X] it creates and initializes the pool, creates a pool token, deposits into the pool token, transfers the LP token to the seller and transfers any excess back to the seller

    function test_givenPoolIsCreated()
        public
        givenCallbackIsCreated
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenProceedsUtilisationPercent_fuzz(uint24 percent_)
        public
        givenCallbackIsCreated
        givenUnboundedProceedsUtilisationPercent(percent_)
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenCurationPayout_fuzz(uint96 curationPayout_)
        public
        givenCallbackIsCreated
        givenOnCreate
        givenUnboundedOnCurate(curationPayout_)
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenProceedsUtilisationPercent_givenCurationPayout_fuzz(
        uint24 percent_,
        uint96 curationPayout_
    )
        public
        givenCallbackIsCreated
        givenUnboundedProceedsUtilisationPercent(percent_)
        givenOnCreate
        givenUnboundedOnCurate(curationPayout_)
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_whenRefund_fuzz(uint96 refund_)
        public
        givenCallbackIsCreated
        givenOnCreate
        whenRefundIsBounded(refund_)
        setCallbackParameters(_PROCEEDS, _refund)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenPoolHasDepositWithLowerPrice_reverts()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenPoolIsCreated
        givenPoolHasDepositLowerPrice
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        // Expect revert
        vm.expectRevert("INSUFFICIENT B");

        _performOnSettle();
    }

    function test_givenPoolHasDepositWithLowerPrice_whenMaxSlippageIsSet()
        public
        givenCallbackIsCreated
        givenMaxSlippage(500) // 5%
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenPoolIsCreated
        givenPoolHasDepositLowerPrice
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenPoolHasDepositWithHigherPrice_reverts()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenPoolIsCreated
        givenPoolHasDepositHigherPrice
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        // Expect revert
        vm.expectRevert("INSUFFICIENT A");

        _performOnSettle();
    }

    function test_givenPoolHasDepositWithHigherPrice_whenMaxSlippageIsSet()
        public
        givenCallbackIsCreated
        givenMaxSlippage(500) // 5%
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenPoolIsCreated
        givenPoolHasDepositHigherPrice
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenVesting()
        public
        givenLinearVestingModuleIsInstalled
        givenCallbackIsCreated
        givenVestingStart(_initialTimestamp + 1)
        givenVestingExpiry(_initialTimestamp + 2)
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenVesting_whenRecipientIsNotSeller()
        public
        givenLinearVestingModuleIsInstalled
        givenCallbackIsCreated
        givenVestingStart(_initialTimestamp + 1)
        givenVestingExpiry(_initialTimestamp + 2)
        whenRecipientIsNotSeller
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenVesting_redemption()
        public
        givenLinearVestingModuleIsInstalled
        givenCallbackIsCreated
        givenVestingStart(_initialTimestamp + 1)
        givenVestingExpiry(_initialTimestamp + 2)
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        // Warp to the end of the vesting period
        vm.warp(_initialTimestamp + 3);

        // Redeem the vesting tokens
        uint256 tokenId = _getVestingTokenId();
        vm.prank(_SELLER);
        _linearVesting.redeemMax(tokenId);

        // Assert that the LP token has been transferred to the seller
        ICleopatraV1Pool pool = _getCleopatraV1Pool();
        assertEq(
            pool.balanceOf(_SELLER),
            pool.totalSupply() - _MINIMUM_LIQUIDITY,
            "seller: LP token balance"
        );
    }

    function test_withdrawLpToken()
        public
        givenCallbackIsCreated
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        // Get the pools deployed by the DTL callback
        ICleopatraV1Pool pool = _getCleopatraV1Pool();

        // Approve the spending of the LP token
        uint256 lpTokenAmount = pool.balanceOf(_SELLER);
        vm.prank(_SELLER);
        pool.approve(address(_router), lpTokenAmount);

        // Withdraw the LP token
        vm.prank(_SELLER);
        _router.removeLiquidity(
            address(_quoteToken),
            address(_baseToken),
            _cleopatraCreateParams.stable,
            lpTokenAmount,
            _quoteTokensToDeposit * 99 / 100,
            _baseTokensToDeposit * 99 / 100,
            _SELLER,
            block.timestamp
        );

        // Get the minimum liquidity retained in the pool
        uint256 quoteTokenPoolAmount = _quoteToken.balanceOf(address(pool));
        uint256 baseTokenPoolAmount = _baseToken.balanceOf(address(pool));

        // Check the balances
        assertEq(pool.balanceOf(_SELLER), 0, "seller: LP token balance");
        assertEq(
            _quoteToken.balanceOf(_SELLER),
            _proceeds - quoteTokenPoolAmount,
            "seller: quote token balance"
        );
        assertEq(
            _baseToken.balanceOf(_SELLER),
            _capacityUtilised - baseTokenPoolAmount,
            "seller: base token balance"
        );
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "DTL: quote token balance");
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "DTL: base token balance");
    }

    function test_givenInsufficientBaseTokenBalance_reverts()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised - 1)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BaseDirectToLiquidity.Callback_InsufficientBalance.selector,
            address(_baseToken),
            _SELLER,
            _baseTokensToDeposit,
            _baseTokensToDeposit - 1
        );
        vm.expectRevert(err);

        _performOnSettle();
    }

    function test_givenInsufficientBaseTokenAllowance_reverts()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised - 1)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        _performOnSettle();
    }

    function test_success()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_success_multiple()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_NOT_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_NOT_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Create second lot
        uint96 lotIdTwo = _createLot(_NOT_SELLER);

        _performOnSettle(lotIdTwo);

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_stablePool()
        public
        givenCallbackIsCreated
        givenStable(true)
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        address stablePool = address(_getCleopatraV1Pool(true));
        address volatilePool = address(_getCleopatraV1Pool(false));

        assertNotEq(stablePool, address(0), "stable pool address");
        assertEq(volatilePool, address(0), "volatile pool address");
    }

    function test_volatilePool()
        public
        givenCallbackIsCreated
        givenStable(false)
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        address stablePool = address(_getCleopatraV1Pool(true));
        address volatilePool = address(_getCleopatraV1Pool(false));

        assertEq(stablePool, address(0), "stable pool address");
        assertNotEq(volatilePool, address(0), "volatile pool address");
    }

    function test_whenRecipientIsNotSeller()
        public
        givenCallbackIsCreated
        whenRecipientIsNotSeller
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_auctionCompleted_onCreate_reverts()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        // Expect revert
        // BaseCallback determines if the lot has already been registered
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        // Try to call onCreate again
        _performOnCreate();
    }

    function test_auctionCompleted_onCurate_reverts()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        // Expect revert
        // BaseDirectToLiquidity determines if the lot has already been completed
        bytes memory err =
            abi.encodeWithSelector(BaseDirectToLiquidity.Callback_AlreadyComplete.selector);
        vm.expectRevert(err);

        // Try to call onCurate
        _performOnCurate(_curatorPayout);
    }

    function test_auctionCompleted_onCancel_reverts()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        // Expect revert
        // BaseDirectToLiquidity determines if the lot has already been completed
        bytes memory err =
            abi.encodeWithSelector(BaseDirectToLiquidity.Callback_AlreadyComplete.selector);
        vm.expectRevert(err);

        // Try to call onCancel
        _performOnCancel();
    }

    function test_auctionCompleted_onSettle_reverts()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        // Expect revert
        // BaseDirectToLiquidity determines if the lot has already been completed
        bytes memory err =
            abi.encodeWithSelector(BaseDirectToLiquidity.Callback_AlreadyComplete.selector);
        vm.expectRevert(err);

        // Try to call onSettle
        _performOnSettle();
    }
}
