# axis-periphery

This repository contains non-core contracts from the Axis Finance system.

## Developer Guide

Axis is built in Solidity using Foundry as the development and test environment. The following commands are available for development:

### First-Run

```shell
pnpm install
```

### Build

```shell
forge build
```

### Test

The test suite can be run with:

```shell
pnpm run test
```

### Format

Combines `forge fmt` and `solhint`

```shell
pnpm run lint
```

To run linting on all files (including tests and scripts):

```shell
pnpm run lint:all
```

### Scripts

Scripts are written in Solidity using Foundry and are divided into `deploy`, `salts` and `ops` scripts. Specific scripts are written for individual actions and can be found in the `scripts` directory along with shell scripts to run them.

### Deployments

Deployments are listed in the [env.json file](/script/env.json) and periodically updated in the [Axis documentation](https://axis.finance/developer/reference/contract-addresses).

### Dependencies

[soldeer](https://soldeer.xyz/) is used as the dependency manager, as it solves many of the problems inherent in forge's use of git submodules. Soldeer is integrated into `forge`, so should not require any additional installations.

NOTE: The import path of each dependency is versioned. This ensures that any changes to the dependency version result in clear errors to highlight the potentially-breaking change.

#### Updating Dependencies

When updating the version of a dependency provided through soldeer, the following must be performed:

1. Update the version of the dependency in `foundry.toml` or through `forge soldeer`
2. Re-run the [installation script](#first-run)
3. If the version number has changed:
   - Change the existing entry in [remappings.txt](remappings.txt) to point to the new dependency version
   - Update imports to use the new remapping

#### Updating axis-core

Updating the version of the `axis-core` dependency is a special case, as some files are accessed directly and bypass remappings. Perform the following after following the [steps above](#updating-dependencies):

1. Update the version in the `axis-core` entry for the `fs_permissions` key in [foundry.toml](foundry.toml)
2. Update the version mentioned in `_loadEnv()` in the [WithEnvironment](script/deploy/WithEnvironment.s.sol) contract

### Packaging

To publish a new package version to soldeer, run the following:

```shell
pnpm run publish <version>
```

On first run, this requires authentication with soldeer: `soldeer login`

The [CHANGELOG](CHANGELOG.md) file should also be updated.
