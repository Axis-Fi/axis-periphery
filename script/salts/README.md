# Salts

This document provides instructions on how to generate and use salts for CREATE2 deployments to deterministic addresses.

## Tasks

### Generating Salts for Batch Allowlists

The following command will generate salts for the batch allowlist sequence:

```bash
./script/salts/allowlist/allowlist_salts.sh --deployFile ./script/deploy/sequences/batch-allowlists.json
```

### Generating Salts for Uniswap Direct to Liquidity

The following command will generate salts for any Uniswap DTL callbacks in the specified deployment sequence file:

```bash
./script/salts/dtl-uniswap/uniswap_dtl_salts.sh --deployFile <filePath>
```

### Generating Salts for Any Contract

For aesthetic, gas or other reasons, certain contracts will need to be deployed at deterministic addresses.

The following steps need to be followed to generate the salt:

1. Generate the bytecode file and write it to disk. See `AllowlistSalts.s.sol` for an example.

1. Run the salts script with the desired prefix, salt key and bytecode hash. For example:

```bash
./scripts/salts/write_salt.sh ./bytecode/CappedMerkleAllowlist98.bin 98 CappedMerkleAllowlist 0x5080f4a157b896da527e936ac326bc3742c5d0239c63823b4d5c9939cc19ccb1
```

Provided the contract bytecode (contract code and constructor arguments) is the same, the saved salt will be used during deployment.
