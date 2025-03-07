// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV3DirectToLiquidityTest} from "./UniswapV3DTLTest.sol";

// Libraries
import {FixedPointMathLib} from "@solmate-6.8.0/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate-6.8.0/tokens/ERC20.sol";

// Uniswap
import {IUniswapV3Pool} from
    "@uniswap-v3-core-1.0.1-solc-0.8-simulate/interfaces/IUniswapV3Pool.sol";
import {SqrtPriceMath} from "../../../../src/lib/uniswap-v3/SqrtPriceMath.sol";
import {TickMath} from "@uniswap-v3-core-1.0.1-solc-0.8-simulate/libraries/TickMath.sol";

// G-UNI
import {GUniPool} from "@g-uni-v1-core-0.9.9/GUniPool.sol";

// AuctionHouse
import {ILinearVesting} from "@axis-core-1.0.4/interfaces/modules/derivatives/ILinearVesting.sol";
import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";
import {UniswapV3DirectToLiquidity} from "../../../../src/callbacks/liquidity/UniswapV3DTL.sol";
import {BaseCallback} from "@axis-core-1.0.4/bases/BaseCallback.sol";

import {console2} from "@forge-std-1.9.1/console2.sol";

contract UniswapV3DirectToLiquidityOnSettleTest is UniswapV3DirectToLiquidityTest {
    uint96 internal constant _PROCEEDS = 20e18;
    uint96 internal constant _REFUND = 0;

    uint96 internal _capacityUtilised;
    uint96 internal _quoteTokensToDeposit;
    uint96 internal _baseTokensToDeposit;
    uint96 internal _curatorPayout;
    uint256 internal _additionalQuoteTokensMinted;

    uint160 internal constant _SQRT_PRICE_X96_OVERRIDE = 125_270_724_187_523_965_593_206_000_000; // Different to what is normally calculated

    /// @dev Set via `setCallbackParameters` modifier
    uint160 internal _sqrtPriceX96;

    // ========== Internal functions ========== //

    function _getGUniPool() internal view returns (GUniPool) {
        // Get the pools deployed by the DTL callback
        address[] memory pools = _gUniFactory.getPools(_dtlAddress);

        return GUniPool(pools[0]);
    }

    function _getVestingTokenId() internal view returns (uint256) {
        // Get the pools deployed by the DTL callback
        address pool = address(_getGUniPool());

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

    function _assertPoolState(
        uint160 sqrtPriceX96_
    ) internal view {
        // Get the pool
        IUniswapV3Pool pool = _getPool();

        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        assertEq(sqrtPriceX96, sqrtPriceX96_, "pool sqrt price");
    }

    function _assertLpTokenBalance() internal view {
        // Get the pools deployed by the DTL callback
        GUniPool pool = _getGUniPool();

        uint256 sellerExpectedBalance;
        uint256 linearVestingExpectedBalance;
        // Only has a balance if not vesting
        if (_dtlCreateParams.vestingStart == 0) {
            sellerExpectedBalance = pool.totalSupply();
        } else {
            linearVestingExpectedBalance = pool.totalSupply();
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
        address pool = address(_getGUniPool());

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

        uint256 nonPoolProceeds = _proceeds - _quoteTokensToDeposit;
        assertApproxEqAbs(
            _quoteToken.balanceOf(_NOT_SELLER),
            _dtlCreateParams.recipient == _NOT_SELLER ? nonPoolProceeds : 0,
            (
                _dtlCreateParams.recipient == _NOT_SELLER
                    ? _uniswapV3CreateParams.maxSlippage * _quoteTokensToDeposit / 100e2
                    : 0
            ) + 2, // Rounding errors
            "not seller: quote token balance"
        );
        assertApproxEqAbs(
            _quoteToken.balanceOf(_SELLER),
            _dtlCreateParams.recipient == _SELLER ? nonPoolProceeds : 0,
            (
                _dtlCreateParams.recipient == _NOT_SELLER
                    ? _uniswapV3CreateParams.maxSlippage * _quoteTokensToDeposit / 100e2
                    : 0
            ) + 2, // Rounding errors
            "seller: quote token balance"
        );
    }

    function _assertBaseTokenBalance() internal view {
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "DTL: base token balance");
    }

    function _assertApprovals() internal view {
        // Ensure there are no dangling approvals
        assertEq(
            _quoteToken.allowance(_dtlAddress, address(_getGUniPool())),
            0,
            "DTL: quote token allowance"
        );
        assertEq(
            _baseToken.allowance(_dtlAddress, address(_getGUniPool())),
            0,
            "DTL: base token allowance"
        );
    }

    // ========== Modifiers ========== //

    function _createPool() internal returns (address) {
        (address token0, address token1) = address(_baseToken) < address(_quoteToken)
            ? (address(_baseToken), address(_quoteToken))
            : (address(_quoteToken), address(_baseToken));

        return _uniV3Factory.createPool(token0, token1, _poolFee);
    }

    function _initializePool(address pool_, uint160 sqrtPriceX96_) internal {
        IUniswapV3Pool(pool_).initialize(sqrtPriceX96_);
    }

    modifier givenPoolIsCreated() {
        _createPool();
        _;
    }

    modifier givenPoolIsCreatedAndInitialized(
        uint160 sqrtPriceX96_
    ) {
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
        _quoteTokensToDeposit = _proceeds * _dtlCreateParams.poolPercent / 100e2;
        _baseTokensToDeposit = _capacityUtilised * _dtlCreateParams.poolPercent / 100e2;

        _sqrtPriceX96 = _calculateSqrtPriceX96(_quoteTokensToDeposit, _baseTokensToDeposit);
        _;
    }

    modifier givenUnboundedPoolPercent(
        uint24 percent_
    ) {
        // Bound the percent
        uint24 percent = uint24(bound(percent_, 10e2, 100e2));

        // Set the value on the DTL
        _dtlCreateParams.poolPercent = percent;
        _;
    }

    modifier givenUnboundedOnCurate(
        uint96 curationPayout_
    ) {
        // Bound the value
        _curatorPayout = uint96(bound(curationPayout_, 1e17, _LOT_CAPACITY));

        // Call the onCurate callback
        _performOnCurate(_curatorPayout);
        _;
    }

    modifier whenRefundIsBounded(
        uint96 refund_
    ) {
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

    modifier givenPoolHasDepositMuchHigherPrice() {
        _sqrtPriceX96 = _calculateSqrtPriceX96(_PROCEEDS * 10, _LOT_CAPACITY);
        _;
    }

    function _getPool() internal view returns (IUniswapV3Pool) {
        (address token0, address token1) = address(_baseToken) < address(_quoteToken)
            ? (address(_baseToken), address(_quoteToken))
            : (address(_quoteToken), address(_baseToken));
        return IUniswapV3Pool(_uniV3Factory.getPool(token0, token1, _poolFee));
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
    // [X] given there is liquidity in the pool at a higher tick
    //  [X] it adjusts the pool price
    // [X] given there is liquidity in the pool at a lower tick
    //  [X] it adjusts the pool price
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

        _assertPoolState(_sqrtPriceX96);
        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenPoolPercent_fuzz(
        uint24 percent_
    )
        public
        givenCallbackIsCreated
        givenUnboundedPoolPercent(percent_)
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
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenCurationPayout_fuzz(
        uint96 curationPayout_
    )
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
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenPoolPercent_givenCurationPayout_fuzz(
        uint24 percent_,
        uint96 curationPayout_
    )
        public
        givenCallbackIsCreated
        givenUnboundedPoolPercent(percent_)
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
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_whenRefund_fuzz(
        uint96 refund_
    )
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
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenPoolHasDepositWithLowerPrice()
        public
        givenCallbackIsCreated
        givenMaxSlippage(200) // 2%
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenPoolHasDepositLowerPrice
        givenPoolIsCreatedAndInitialized(_sqrtPriceX96)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertPoolState(_calculateSqrtPriceX96(_PROCEEDS, _LOT_CAPACITY));
        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    // TODO need to add a case where the price is more than 2x the target price and there is too much liquidity to sell through
    // the result should be the pool is initialized at a higher price than the target price, but with balanced liquidity
    function test_givenPoolHasDepositWithHigherPrice()
        public
        givenCallbackIsCreated
        givenMaxSlippage(200) // 2%
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenPoolHasDepositHigherPrice
        givenPoolIsCreatedAndInitialized(_sqrtPriceX96)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertPoolState(_calculateSqrtPriceX96(_PROCEEDS, _LOT_CAPACITY));
        _assertLpTokenBalance();
        _assertVestingTokenBalance();
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
        _assertVestingTokenBalance();
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
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            UniswapV3DirectToLiquidity.Callback_Slippage.selector,
            address(_quoteToken),
            19_999_999_999_999_999_999, // Hardcoded
            _quoteTokensToDeposit
        );
        vm.expectRevert(err);

        _performOnSettle();
    }

    function test_givenVesting()
        public
        givenLinearVestingModuleIsInstalled
        givenCallbackIsCreated
        givenVestingStart(_AUCTION_CONCLUSION + 1)
        givenVestingExpiry(_AUCTION_CONCLUSION + 2)
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertPoolState(_sqrtPriceX96);
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
        givenVestingStart(_AUCTION_CONCLUSION + 1)
        givenVestingExpiry(_AUCTION_CONCLUSION + 2)
        whenRecipientIsNotSeller
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        _assertPoolState(_sqrtPriceX96);
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
        givenVestingStart(_AUCTION_CONCLUSION + 1)
        givenVestingExpiry(_AUCTION_CONCLUSION + 2)
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _baseTokensToDeposit)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _baseTokensToDeposit)
    {
        _performOnSettle();

        // Warp to the end of the vesting period
        vm.warp(_AUCTION_CONCLUSION + 3);

        // Check that there is a vested token balance
        uint256 tokenId = _getVestingTokenId();
        uint256 redeemable = _linearVesting.redeemable(_SELLER, tokenId);
        assertGt(redeemable, 0, "redeemable");

        // Redeem the vesting tokens
        vm.prank(_SELLER);
        _linearVesting.redeemMax(tokenId);

        // Assert that the LP token has been transferred to the seller
        GUniPool pool = _getGUniPool();
        assertEq(pool.balanceOf(_SELLER), pool.totalSupply(), "seller: LP token balance");
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
        address[] memory pools = _gUniFactory.getPools(_dtlAddress);
        assertEq(pools.length, 1, "pools length");
        GUniPool pool = GUniPool(pools[0]);

        IUniswapV3Pool uniPool = _getPool();

        // Withdraw the LP token
        uint256 sellerBalance = pool.balanceOf(_SELLER);
        vm.prank(_SELLER);
        pool.burn(sellerBalance, _SELLER);

        // Check the balances
        assertEq(pool.balanceOf(_SELLER), 0, "seller: LP token balance");
        assertEq(_quoteToken.balanceOf(_SELLER), _proceeds - 1, "seller: quote token balance");
        assertEq(_baseToken.balanceOf(_SELLER), _capacityUtilised - 1, "seller: base token balance");
        assertEq(_quoteToken.balanceOf(pools[0]), 0, "pool: quote token balance");
        assertEq(_baseToken.balanceOf(pools[0]), 0, "pool: base token balance");
        assertEq(_quoteToken.balanceOf(_dtlAddress), 0, "DTL: quote token balance");
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "DTL: base token balance");
        // There is a rounding error when burning the LP token, which leaves dust in the pool
        assertEq(_quoteToken.balanceOf(address(uniPool)), 1, "uni pool: quote token balance");
        assertEq(_baseToken.balanceOf(address(uniPool)), 1, "uni pool: base token balance");
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

    function uniswapV3MintCallback(uint256, uint256 amount1Owed, bytes calldata) external {
        console2.log("Minting additional quote tokens", amount1Owed);
        _additionalQuoteTokensMinted += amount1Owed;

        // Transfer the quote tokens
        _quoteToken.mint(msg.sender, amount1Owed);
    }

    function _mintPosition(int24 tickLower_, int24 tickUpper_) internal {
        // Using PoC: https://github.com/GuardianAudits/axis-1/pull/4/files
        IUniswapV3Pool pool = _getPool();

        pool.mint(address(this), tickLower_, tickUpper_, 1e18, "");
    }

    function uniswapV3SwapCallback(int256, int256, bytes memory) external pure {
        return;
    }

    function _swap(
        uint160 sqrtPrice_
    ) internal {
        IUniswapV3Pool pool = _getPool();

        pool.swap(address(this), true, 1, sqrtPrice_, "");
    }

    function test_existingReservesAtHigherPoolTick()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
        givenPoolIsCreatedAndInitialized(_sqrtPriceX96)
    {
        // Assert the pool price
        int24 poolTick;
        (, poolTick,,,,,) = _getPool().slot0();
        assertEq(poolTick, 6931, "pool tick after mint"); // Original active tick

        // Swap at a tick higher than the anchor range
        IUniswapV3Pool pool = _getPool();
        pool.swap(address(this), false, 1, TickMath.getSqrtRatioAtTick(60_000), "");

        // Assert that the pool tick has moved higher
        (, poolTick,,,,,) = _getPool().slot0();
        assertEq(poolTick, 60_000, "pool tick after swap");

        // Provide reserve tokens to the pool at a tick higher than the original active tick and lower than the new active tick
        _mintPosition(7200, 7200 + _getPool().tickSpacing());

        // Perform callback
        _performOnSettle();

        // Assert that the pool tick has corrected
        (, poolTick,,,,,) = _getPool().slot0();
        assertEq(poolTick, 6931, "pool tick after settlement"); // Ends up rounded to the tick spacing

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        // _assertQuoteTokenBalance(); // Difficult to calculate the exact balance, given the swaps
        // _assertBaseTokenBalance(); // Difficult to calculate the exact balance, given the swaps
        _assertApprovals();
    }

    function test_existingReservesAtHigherPoolTick_noLiquidity()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
        givenPoolIsCreatedAndInitialized(_sqrtPriceX96)
    {
        // Assert the pool price
        int24 poolTick;
        (, poolTick,,,,,) = _getPool().slot0();
        assertEq(poolTick, 6931, "pool tick after mint"); // Original active tick

        // Swap at a tick higher than the active tick
        IUniswapV3Pool pool = _getPool();
        pool.swap(address(this), false, 1, TickMath.getSqrtRatioAtTick(60_000), "");

        // Assert that the pool tick has moved higher
        (, poolTick,,,,,) = _getPool().slot0();
        assertEq(poolTick, 60_000, "pool tick after swap");

        // Do not mint any liquidity above the previous active tick

        // Perform callback
        _performOnSettle();

        // Assert that the pool tick has corrected
        (, poolTick,,,,,) = _getPool().slot0();
        assertEq(poolTick, 6931, "pool tick after settlement"); // Ends up rounded to the tick spacing

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_existingReservesAtLowerPoolTick()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
        givenPoolIsCreatedAndInitialized(_sqrtPriceX96)
    {
        // Provide reserve tokens to the pool at a lower tick
        _mintPosition(-60_000 - _getPool().tickSpacing(), -60_000);

        // Assert the pool price
        int24 poolTick;
        (, poolTick,,,,,) = _getPool().slot0();
        assertEq(poolTick, 6931, "pool tick after mint"); // Original active tick

        // Swap at a tick lower than the active tick
        _swap(TickMath.getSqrtRatioAtTick(-60_000));

        // Assert that the pool price has moved lower
        (, poolTick,,,,,) = _getPool().slot0();
        assertEq(poolTick, -60_001, "pool tick after swap");

        // Perform callback
        _performOnSettle();

        // Assert that the pool tick has corrected
        (, poolTick,,,,,) = _getPool().slot0();
        assertEq(poolTick, 6931, "pool tick after settlement"); // Ends up rounded to the tick spacing

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_existingReservesAtLowerPoolTick_noLiquidity()
        public
        givenCallbackIsCreated
        givenOnCreate
        setCallbackParameters(_PROCEEDS, _REFUND)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
        givenPoolIsCreatedAndInitialized(_sqrtPriceX96)
    {
        // Don't mint any liquidity

        // Assert the pool price
        int24 poolTick;
        (, poolTick,,,,,) = _getPool().slot0();
        assertEq(poolTick, 6931, "pool tick after mint"); // Original active tick

        // Swap at a tick lower than the active tick
        _swap(TickMath.getSqrtRatioAtTick(-60_000));

        // Assert that the pool price has moved lower
        (, poolTick,,,,,) = _getPool().slot0();
        assertEq(poolTick, -60_000, "pool tick after swap");

        // Perform callback
        _performOnSettle();

        // Assert that the pool tick has corrected
        (, poolTick,,,,,) = _getPool().slot0();
        assertEq(poolTick, 6931, "pool tick after settlement"); // Ends up rounded to the tick spacing

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }
}
