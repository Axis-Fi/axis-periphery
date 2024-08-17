## Axis Fuzz Suite

### Overview
Axis engaged Guardian Audits for an in-depth security review of its periphery contracts containing the callback functionality for the core Axis auctions. This comprehensive evaluation, conducted from July 22nd to July 29th, 2024, included the development of a specialized fuzzing suite to uncover complex logical errors. This suite was created during the review period and successfully delivered upon the audit's conclusion.

### Contents
Setup.sol configures the Axis Protocol setup and actors used for fuzzing.

It also concludes a number of handler contracts for each DTL contract in scope:
* UniswapV2DTLHandler.sol
* V2PoolHandler.sol
* UniswapV3DTLHandler.sol
* V3PoolHandler.sol
* BaselineDTLHandler.sol
* BaselinePoolHandler.sol

### Setup And Run Instructions

First, install dependencies:
```shell
pnpm install
```
If an error occurs while soldeer runs during installation, try running soldeer individually:
```shell
soldeer install
```
Then, install forge dependencies:
```shell
forge install
```


To run invariant tests:
```shell
echidna . --contract AxisInvariant --config ./test/invariant/echidna.yaml
```

If a key error occurs (`KeyError: 'output'`) :
```shell
forge clean
```
then try the echidna command again.

### Unexpected Selectors
Due to the issue of the proceeds_ value being based on the total sold less the fees taken by the protocol and referrer, the handler function `baselineDTL_onSettle` will throw an assertion fail with the error selector `Callback_InvalidCapacityRatio`

### Invariants
## **Axis**
| **Invariant ID** | **Invariant Description** | **Passed** | **Remediation** | **Run Count** |
|:--------------:|:-----|:-----------:|:-----------:|:-----------:|
| **AX-01** | UniswapV2Dtl_onCreate() should set DTL Config recipient | PASS | PASS | 10,000,000+
| **AX-02** | UniswapV2Dtl_onCreate() should set DTL Config lotCapacity | PASS | PASS | 10,000,000+
| **AX-03** | UniswapV2Dtl_onCreate() should set DTL Config lotCuratorPayout | PASS | PASS | 10,000,000+
| **AX-04** | UniswapV2Dtl_onCreate() should set DTL Config proceedsUtilisationPercent | PASS | PASS | 10,000,000+
| **AX-05** | UniswapV2Dtl_onCreate() should set DTL Config vestingStart | PASS | PASS | 10,000,000+
| **AX-06** | UniswapV2Dtl_onCreate() should set DTL Config vestingExpiry | PASS | PASS | 10,000,000+
| **AX-07** | UniswapV2Dtl_onCreate() should set DTL Config linearVestingModule | PASS | PASS | 10,000,000+
| **AX-08** | UniswapV2Dtl_onCreate() should set DTL Config active to true | PASS | PASS | 10,000,000+
| **AX-09** | DTL Callbacks should not change seller base token balance | PASS | PASS | 10,000,000+
| **AX-10** | DTL Callbacks should not change dtl base token balance | PASS | PASS | 10,000,000+
| **AX-11** | DTL_onCancel() should set DTL Config active to false | PASS | PASS | 10,000,000+
| **AX-12** | DTL_onCurate should set DTL Config lotCuratorPayout | PASS | PASS | 10,000,000+
| **AX-13** | When calling DTL_onCurate auction house base token balance should be equal to lot Capacity of each lotId | PASS | PASS | 10,000,000+
| **AX-14** | DTL_onSettle should should credit seller the expected LP token balance | PASS | PASS | 10,000,000+
| **AX-15** | DTL_onSettle should should credit linearVestingModule the expected LP token balance | PASS | PASS | 10,000,000+
| **AX-16** | DTL_onSettle should should credit seller the expected wrapped vesting token balance | PASS | PASS | 10,000,000+
| **AX-17** | After DTL_onSettle DTL Address quote token balance should equal 0 | PASS | PASS | 10,000,000+
| **AX-18** | After DTL_onSettle DTL Address base token balance should equal 0 | PASS | PASS | 10,000,000+
| **AX-19** | After UniswapV2DTL_onSettle DTL Address quote token allowance for the UniswapV2 Router should equal 0 | PASS | PASS | 10,000,000+
| **AX-20** | After UniswapV2DTL_onSettle DTL Address base token allowance UniswapV2 Router should equal 0 | PASS | PASS | 10,000,000+
| **AX-21** | UniswapV3Dtl_onCreate() should set DTL Config recipient | PASS | PASS | 10,000,000+
| **AX-22** | UniswapV3Dtl_onCreate() should set DTL Config lotCapacity| PASS | PASS | 10,000,000+
| **AX-23** | UniswapV3Dtl_onCreate() should set DTL Config lotCuratorPayout | PASS | PASS | 10,000,000+
| **AX-24** | UniswapV3Dtl_onCreate() should set DTL Config proceedsUtilisationPercent | PASS | PASS | 10,000,000+
| **AX-25** | UniswapV3Dtl_onCreate() should set DTL Config vestingStart | PASS | PASS | 10,000,000+
| **AX-26** | UniswapV3Dtl_onCreate() should set DTL Config vestingExpiry | PASS | PASS | 10,000,000+
| **AX-27** | UniswapV3Dtl_onCreate() should set DTL Config linearVestingModule | PASS | PASS | 10,000,000+
| **AX-28** | UniswapV3Dtl_onCreate() should set DTL Config active to true | PASS | PASS | 10,000,000+
| **AX-29** | On UniswapV3DTL_OnSettle() calculated sqrt price should equal pool sqrt price | PASS | PASS | 10,000,000+
| **AX-30** | After UniswapV3DTL_onSettle DTL Address base token allowance for the GUniPool should equal 0 | PASS | PASS | 10,000,000+
| **AX-31** | After UniswapV3DTL_onSettle DTL Address base token allowance for the GUniPool should equal 0 | PASS | PASS | 10,000,000+ | PASS | PASS | 10,000,000+
| **AX-32** | When calling BaselineDTL_createLot auction house base token balance should be equal to lot Capacity lotId | PASS | PASS | 10,000,000+
| **AX-33** | After DTL_onSettle quote token balance of quote token should equal 0 | PASS | PASS | 10,000,000+
| **AX-34** | BaselineDTL_onSettle should credit baseline pool with correct quote token proceeds | PASS | PASS | 10,000,000+
| **AX-35** | BaselineDTL_onSettle should credit seller quote token proceeds | PASS | PASS | 10,000,000+
| **AX-36** | Baseline token total supply after _onCancel should equal 0 | PASS | PASS | 10,000,000+
| **AX-37** | BaselineDTL_onCancel should mark auction completed | PASS | PASS | 10,000,000+
| **AX-38** | When calling BaselineDTL_onCancel DTL base token balance should equal 0 | PASS | PASS | 10,000,000+
| **AX-39** | When calling BaselineDTL_onCancel baseline contract base token balance should equal 0 | PASS | PASS | 10,000,000+
| **AX-40** | BaselineDTL_onCurate should credit auction house correct base token fees | PASS | PASS | 10,000,000+
| **AX-41** | After BaselineDTL_onSettle baseline token base token balance should equal 0 | PASS | PASS | 10,000,000+
| **AX-42** | After BaselineDTL_onSettle baseline pool base token balance should equal baseline pool supply | PASS | PASS | 10,000,000+
| **AX-43** | After BaselineDTL_onSettle seller baseline token balance should equal 0 | PASS | PASS | 10,000,000+
| **AX-44** | circulating supply should equal lot capacity plus curatorFee minus refund | PASS | PASS | 10,000,000+
| **AX-45** | BaselineDTL_onSettle should mark auction complete | PASS | PASS | 10,000,000+
| **AX-46** | After BaselineDTL_onSettle floor reserves should equal floor proceeds | PASS | PASS | 10,000,000+
| **AX-47** | After BaselineDTL_onSettle anchor reserves should equal pool proceeds - floor proceeds | PASS | PASS | 10,000,000+
| **AX-48** | After BaselineDTL_onSettle discovery reserves should equal 0 | PASS | PASS | 10,000,000+
| **AX-49** | After BaselineDTL_onSettle floor bAssets should equal 0 | PASS | PASS | 10,000,000+
| **AX-50** | After BaselineDTL_onSettle anchor bAssets should be greater than 0 | PASS | PASS | 10,000,000+
| **AX-51** | After BaselineDTL_onSettle discovery bAssets should be greater than 0 | PASS | PASS | 10,000,000+
| **AX-52** | UniswapV2DTL_onSettle should not fail with 'UniswapV2Library: INSUFFICIENT_LIQUIDITY' | **FAIL** | **FAIL** | 10,000,000+
| **AX-53** | Profit should not be extractable due to UniswapV3Pool price manipulation | **FAIL** | PASS | 10,000,000+