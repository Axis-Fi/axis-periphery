// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {UniswapV2DirectToLiquidityTest} from "./UniswapV2DTLTest.sol";

// Libraries
import {FixedPointMathLib} from "@solmate-6.8.0/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate-6.8.0/tokens/ERC20.sol";

// Uniswap
import {IUniswapV2Pair} from "@uniswap-v2-core-1.0.1/interfaces/IUniswapV2Pair.sol";

// AuctionHouse
import {ILinearVesting} from "@axis-core-1.0.4/interfaces/modules/derivatives/ILinearVesting.sol";
import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";
import {BaseCallback} from "@axis-core-1.0.4/bases/BaseCallback.sol";

import {console2} from "@forge-std-1.9.1/console2.sol";

contract UniswapV2DirectToLiquidityOnSettleTest is UniswapV2DirectToLiquidityTest {
    uint96 internal constant _PROCEEDS = 20e18;
    uint96 internal constant _REFUND = 0;

    uint96 internal constant _PROCEEDS_PRICE_LESS_THAN_ONE = 5e18;

    /// @dev The minimum amount of liquidity retained in the pool
    uint256 internal constant _MINIMUM_LIQUIDITY = 10 ** 3;

    uint96 internal _capacityUtilised;
    uint96 internal _quoteTokensToDeposit;
    uint96 internal _baseTokensToDeposit;
    uint96 internal _curatorPayout;
    uint256 internal _auctionPrice;
    uint256 internal _quoteTokensDonated;

    // ========== Internal functions ========== //

    function _getUniswapV2Pool() internal view returns (IUniswapV2Pair) {
        return IUniswapV2Pair(_uniV2Factory.getPair(address(_quoteToken), address(_baseToken)));
    }

    function _getVestingTokenId() internal view returns (uint256) {
        // Get the pools deployed by the DTL callback
        address pool = address(_getUniswapV2Pool());

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
        IUniswapV2Pair pool = _getUniswapV2Pool();

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

    function _assertLpUnderlyingBalances() internal view {
        // Get the pools deployed by the DTL callback
        IUniswapV2Pair pool = _getUniswapV2Pool();
        address poolAddress = address(pool);

        // Check the underlying balances
        assertGe(
            _quoteToken.balanceOf(poolAddress), _quoteTokensToDeposit, "pair: quote token balance"
        );
        assertApproxEqRel(
            _baseToken.balanceOf(poolAddress),
            _baseTokensToDeposit,
            1e14, // 0.01%
            "pair: base token balance"
        );

        // Check that the reserves match
        (uint256 reserve0, uint256 reserve1,) = pool.getReserves();
        bool quoteTokenIsToken0 = pool.token0() == address(_quoteToken);
        assertGe(
            quoteTokenIsToken0 ? reserve0 : reserve1,
            _quoteTokensToDeposit,
            "pair: quote token reserve"
        );
        assertApproxEqRel(
            quoteTokenIsToken0 ? reserve1 : reserve0,
            _baseTokensToDeposit,
            1e14, // 0.01%
            "pair: base token reserve"
        );

        // Assert the price of the pool
        assertApproxEqRel(
            FixedPointMathLib.mulDivDown(
                _quoteToken.balanceOf(poolAddress),
                10 ** _baseToken.decimals(),
                _baseToken.balanceOf(poolAddress)
            ),
            _auctionPrice,
            1e14, // 0.01%
            "pair: price"
        );
    }

    function _assertVestingTokenBalance() internal {
        // Exit if not vesting
        if (_dtlCreateParams.vestingStart == 0) {
            return;
        }

        // Get the pools deployed by the DTL callback
        address pool = address(_getUniswapV2Pool());

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

        uint256 nonPoolProceeds = _proceeds + _quoteTokensDonated - _quoteTokensToDeposit;
        assertApproxEqAbs(
            _quoteToken.balanceOf(_NOT_SELLER),
            _dtlCreateParams.recipient == _NOT_SELLER ? nonPoolProceeds : 0,
            _dtlCreateParams.recipient == _NOT_SELLER
                ? _uniswapV2CreateParams.maxSlippage * _quoteTokensToDeposit / 100e2
                : 0,
            "not seller: quote token balance"
        );
        assertApproxEqAbs(
            _quoteToken.balanceOf(_SELLER),
            _dtlCreateParams.recipient == _SELLER ? nonPoolProceeds : 0,
            _dtlCreateParams.recipient == _SELLER
                ? _uniswapV2CreateParams.maxSlippage * _quoteTokensToDeposit / 100e2
                : 0,
            "seller: quote token balance"
        );
    }

    function _assertBaseTokenBalance() internal view {
        assertEq(_baseToken.balanceOf(_dtlAddress), 0, "DTL: base token balance");

        // TODO check the base token balance for the seller
    }

    function _assertApprovals() internal view {
        // Ensure there are no dangling approvals
        assertEq(
            _quoteToken.allowance(_dtlAddress, address(_uniV2Router)),
            0,
            "DTL: quote token allowance"
        );
        assertEq(
            _baseToken.allowance(_dtlAddress, address(_uniV2Router)), 0, "DTL: base token allowance"
        );
    }

    // ========== Modifiers ========== //

    function _createPool() internal returns (address) {
        return _uniV2Factory.createPair(address(_quoteToken), address(_baseToken));
    }

    modifier givenPoolIsCreated() {
        _createPool();
        _;
    }

    function _syncPool() internal {
        _getUniswapV2Pool().sync();
    }

    modifier givenPoolSync() {
        _syncPool();
        _;
    }

    modifier setCallbackParameters(uint96 proceeds_, uint96 refund_) {
        // Adjust for the decimals
        _proceeds = uint96(proceeds_ * 10 ** _quoteToken.decimals() / 1e18);
        _refund = uint96(refund_ * 10 ** _baseToken.decimals() / 1e18);

        // Calculate the capacity utilised
        // Any unspent curator payout is included in the refund
        // However, curator payouts are linear to the capacity utilised
        // Calculate the percent utilisation
        uint96 capacityUtilisationPercent = 100e2
            - uint96(FixedPointMathLib.mulDivDown(_refund, 100e2, _lotCapacity + _curatorPayout));
        _capacityUtilised = _lotCapacity * capacityUtilisationPercent / 100e2;

        // The pool percent scales the quote tokens and base tokens linearly
        _quoteTokensToDeposit = _proceeds * _dtlCreateParams.poolPercent / 100e2;
        _baseTokensToDeposit = _capacityUtilised * _dtlCreateParams.poolPercent / 100e2;

        _auctionPrice = _proceeds * 10 ** _baseToken.decimals() / (_lotCapacity - _refund);
        console2.log("Derived auction price is: ", _auctionPrice);
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
        _curatorPayout = uint96(bound(curationPayout_, 1e17, _lotCapacity));

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

    // ========== Tests ========== //

    // [X] given the onSettle callback has already been called
    //  [X] when onSettle is called
    //   [X] it reverts
    //  [X] when onCancel is called
    //   [X] it reverts
    //  [X] when onCurate is called
    //   [X] it reverts
    //  [X] when onCreate is called
    //   [X] it reverts
    // [X] given the pool is created
    //  [X] it initializes the pool
    // [X] given the pool is created and initialized
    //  [X] it succeeds
    // [X] given the pool has quote tokens donated
    //  [X] given the auction price is 1
    //   [X] it corrects the pool price
    //  [X] given the auction price is < 1
    //   [X] it corrects the pool price
    //  [X] given the auction price is > 1
    //   [X] it corrects the pool price
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

        _assertLpTokenBalance();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenAuctionPriceGreaterThanOne_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS, _REFUND) // Price is 2
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e18);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceGreaterThanOne_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS, _REFUND) // Price is 2
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e18);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceGreaterThanOne_givenDifferentQuoteTokenDecimals_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenQuoteTokenDecimals(17)
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS, _REFUND) // Price is 2
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e17);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceGreaterThanOne_givenLowQuoteTokenDecimals_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenQuoteTokenDecimals(6)
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS, _REFUND) // Price is 2
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 1e24);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenAuctionPriceGreaterThanOne_givenDifferentBaseTokenDecimals_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenBaseTokenDecimals(17)
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS, _REFUND) // Price is 2
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e18);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceGreaterThanOne_givenDifferentBaseTokenDecimals_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenBaseTokenDecimals(17)
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS, _REFUND) // Price is 2
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e18);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceGreaterThanOne_givenDecimalPrice_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(15e18, _REFUND) // 1.5e18
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e18);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceGreaterThanOne_givenDecimalPrice_givenDifferentQuoteTokenDecimals_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenQuoteTokenDecimals(17)
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(15e18, _REFUND) // 1.5e17
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e17);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceGreaterThanOne_givenDecimalPrice_givenLowQuoteTokenDecimals_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenQuoteTokenDecimals(6)
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(15e18, _REFUND) // 1.5e6
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 1e24);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceGreaterThanOne_givenDecimalPrice_givenDifferentBaseTokenDecimals_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenBaseTokenDecimals(17)
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(15e18, _REFUND) // 1.5e18
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e18);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenAuctionPriceOne_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_LOT_CAPACITY, 0) // Price = 1
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e18);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceOne_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_LOT_CAPACITY, 0) // Price = 1
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e18);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceOne_givenDifferentQuoteTokenDecimals_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenQuoteTokenDecimals(17)
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_LOT_CAPACITY, 0)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e17);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceOne_givenLowQuoteTokenDecimals_reverts()
        public
        givenCallbackIsCreated
        givenQuoteTokenDecimals(6)
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_LOT_CAPACITY, 0)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // This is a demonstration that a ridiculous quantity of quote tokens will cause
        // the donation mitigation functionality to revert
        uint256 donatedQuoteTokens = 1e24;
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Expect revert
        vm.expectRevert("UniswapV2: K");

        // Callback
        _performOnSettle();
    }

    function test_givenDonation_givenSync_givenAuctionPriceOne_givenDifferentBaseTokenDecimals_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenBaseTokenDecimals(17)
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_LOT_CAPACITY, 0)
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e17);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenAuctionPriceLessThanOne_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS_PRICE_LESS_THAN_ONE, 0) // Price = 0.5
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e18);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceLessThanOne_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS_PRICE_LESS_THAN_ONE, 0) // Price = 0.5
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e18);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceLessThanOne_givenDifferentQuoteTokenDecimals_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenQuoteTokenDecimals(17)
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS_PRICE_LESS_THAN_ONE, 0) // Price = 0.5
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e17);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
        _assertVestingTokenBalance();
        _assertQuoteTokenBalance();
        _assertBaseTokenBalance();
        _assertApprovals();
    }

    function test_givenDonation_givenSync_givenAuctionPriceLessThanOne_givenDifferentBaseTokenDecimals_fuzz(
        uint256 donatedQuoteTokens_
    )
        public
        givenCallbackIsCreated
        givenBaseTokenDecimals(17)
        givenOnCreate
        givenPoolIsCreated
        setCallbackParameters(_PROCEEDS_PRICE_LESS_THAN_ONE, 0) // Price = 0.5
        givenAddressHasQuoteTokenBalance(_dtlAddress, _proceeds)
        givenAddressHasBaseTokenBalance(_SELLER, _capacityUtilised)
        givenAddressHasBaseTokenAllowance(_SELLER, _dtlAddress, _capacityUtilised)
    {
        // Donation amount could be more or less than the auction price
        uint256 donatedQuoteTokens = bound(donatedQuoteTokens_, 1, 3e18);
        _quoteTokensDonated += donatedQuoteTokens;

        // Donate to the pool
        _quoteToken.mint(address(_getUniswapV2Pool()), donatedQuoteTokens);

        // Sync
        _syncPool();

        // Callback
        _performOnSettle();

        // Assertions
        _assertLpTokenBalance();
        _assertLpUnderlyingBalances();
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
        givenVestingStart(_AUCTION_CONCLUSION + 1)
        givenVestingExpiry(_AUCTION_CONCLUSION + 2)
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
        IUniswapV2Pair pool = _getUniswapV2Pool();
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
        IUniswapV2Pair pool = _getUniswapV2Pool();

        // Approve the spending of the LP token
        uint256 lpTokenAmount = pool.balanceOf(_SELLER);
        vm.prank(_SELLER);
        pool.approve(address(_uniV2Router), lpTokenAmount);

        // Withdraw the LP token
        vm.prank(_SELLER);
        _uniV2Router.removeLiquidity(
            address(_quoteToken),
            address(_baseToken),
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
