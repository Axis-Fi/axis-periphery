// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {RamsesV2DirectToLiquidityTest} from "./RamsesV2DTLTest.sol";

// Libraries
import {FixedPointMathLib} from "@solmate-6.7.0/utils/FixedPointMathLib.sol";

// Ramses
import {IRamsesV2Pool} from "../../../../src/callbacks/liquidity/Ramses/lib/IRamsesV2Pool.sol";
import {SqrtPriceMath} from "../../../../src/lib/uniswap-v3/SqrtPriceMath.sol";

// AuctionHouse
import {BaseCallback} from "@axis-core-1.0.0/bases/BaseCallback.sol";
import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";

contract RamsesV2DTLOnSettleForkTest is RamsesV2DirectToLiquidityTest {
    uint96 internal constant _PROCEEDS = 20e18;
    uint96 internal constant _REFUND = 0;

    uint96 internal _capacityUtilised;
    uint96 internal _quoteTokensToDeposit;
    uint96 internal _baseTokensToDeposit;
    uint96 internal _curatorPayout;
    uint24 internal _maxSlippage = 1; // 0.01%

    uint160 internal constant _SQRT_PRICE_X96_OVERRIDE = 125_270_724_187_523_965_593_206_000_000; // Different to what is normally calculated

    /// @dev Set via `setCallbackParameters` modifier
    uint160 internal _sqrtPriceX96;

    // ========== Internal functions ========== //

    function _getTokenId(uint96 lotId_) internal view returns (uint256) {
        return _dtl.lotIdToTokenId(lotId_);
    }

    function _getTokenId() internal view returns (uint256) {
        return _getTokenId(_lotId);
    }

    // ========== Assertions ========== //

    function _assertPoolState(uint160 sqrtPriceX96_) internal view {
        // Get the pool
        address pool = _getPool();

        (uint160 sqrtPriceX96,,,,,,) = IRamsesV2Pool(pool).slot0();
        assertEq(sqrtPriceX96, sqrtPriceX96_, "pool sqrt price");
    }

    function _assertLpTokenBalance(uint96 lotId_, address recipient_) internal view {
        uint256 tokenId = _getTokenId(lotId_);

        assertEq(_positionManager.ownerOf(tokenId), recipient_, "LP token owner");
    }

    function _assertLpTokenBalance() internal view {
        _assertLpTokenBalance(_lotId, _dtlCreateParams.recipient);
    }

    function _assertQuoteTokenBalance() internal view {
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "DTL: quote token balance");
    }

    function _assertBaseTokenBalance() internal view {
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "DTL: base token balance");
    }

    function _assertApprovals() internal view {
        // Router
        assertEq(
            _quoteToken.allowance(address(_dtl), address(_positionManager)),
            0,
            "allowance: quote token: position manager"
        );
        assertEq(
            _baseToken.allowance(address(_dtl), address(_positionManager)),
            0,
            "allowance: base token: position manager"
        );
    }

    // ========== Modifiers ========== //

    function _initializePool(address pool_, uint160 sqrtPriceX96_) internal {
        IRamsesV2Pool(pool_).initialize(sqrtPriceX96_);
    }

    modifier givenPoolIsCreatedAndInitialized(uint160 sqrtPriceX96_) {
        address pool = _createPool();
        _initializePool(pool, sqrtPriceX96_);
        _;
    }

    function _calculateSqrtPriceX96(
        uint256 quoteTokenAmount_,
        uint256 baseTokenAmount_
    ) internal view returns (uint160) {
        return SqrtPriceMath.getSqrtPriceX96(
            address(_quoteToken), address(_baseToken), quoteTokenAmount_, baseTokenAmount_
        );
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

        _sqrtPriceX96 = _calculateSqrtPriceX96(_quoteTokensToDeposit, _baseTokensToDeposit);
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
        _sqrtPriceX96 = _calculateSqrtPriceX96(_PROCEEDS / 2, _LOT_CAPACITY);
        _;
    }

    modifier givenPoolHasDepositHigherPrice() {
        _sqrtPriceX96 = _calculateSqrtPriceX96(_PROCEEDS * 2, _LOT_CAPACITY);
        _;
    }

    function _getPool() internal view returns (address) {
        (address token0, address token1) = address(_baseToken) < address(_quoteToken)
            ? (address(_baseToken), address(_quoteToken))
            : (address(_quoteToken), address(_baseToken));
        return _factory.getPool(token0, token1, _ramsesCreateParams.poolFee);
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
    // [X] given the recipient is not the seller
    //  [X] it mints the LP token to the recipient
    // [X] when multiple lots are created
    //  [X] it performs actions on the correct pool
    // [X] given the veRamTokenId is set
    //  [X] it succeeds
    // [X] it creates and initializes the pool, mints the position, transfers the LP token to the seller and transfers any excess back to the seller

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

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenPoolIsCreatedAndInitialized_givenMaxSlippage()
        public
        givenCallbackIsCreated
        givenMaxSlippage(8100) // 81%
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenPoolIsCreatedAndInitialized(_SQRT_PRICE_X96_OVERRIDE)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        _assertPoolState(_SQRT_PRICE_X96_OVERRIDE);
        _assertLpTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenPoolIsCreatedAndInitialized_reverts()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenPoolIsCreatedAndInitialized(_SQRT_PRICE_X96_OVERRIDE)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Expect revert
        vm.expectRevert("Price slippage check");

        _performOnSettle();
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

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
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

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
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

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
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

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenPoolHasDepositWithLowerPrice()
        public
        givenCallbackIsCreated
        givenMaxSlippage(5100) // 51%
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenPoolHasDepositLowerPrice
        givenPoolIsCreatedAndInitialized(_sqrtPriceX96)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenPoolHasDepositWithHigherPrice()
        public
        givenCallbackIsCreated
        givenMaxSlippage(5100) // 51%
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenPoolHasDepositHigherPrice
        givenPoolIsCreatedAndInitialized(_sqrtPriceX96)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_lessThanMaxSlippage()
        public
        givenCallbackIsCreated
        givenMaxSlippage(1) // 0.01%
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_greaterThanMaxSlippage_reverts()
        public
        givenCallbackIsCreated
        givenMaxSlippage(0) // 0%
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenPoolHasDepositHigherPrice
        givenPoolIsCreatedAndInitialized(_sqrtPriceX96)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        // Expect revert
        vm.expectRevert("Price slippage check");

        _performOnSettle();
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

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
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
        whenRecipientIsNotSeller // Affects the second lot
    {
        // Create second lot
        uint96 lotIdTwo = _createLot(_NOT_SELLER);

        _performOnSettle(lotIdTwo);

        _assertLpTokenBalance(lotIdTwo, _NOT_SELLER);
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
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

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
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

    function test_veRamTokenId()
        public
        givenCallbackIsCreated
        givenVeRamTokenId
        givenVeRamTokenIdApproval(true)
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        _performOnSettle();

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }
}
