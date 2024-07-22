// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {stdJson} from "@forge-std-1.9.1/StdJson.sol";
import {WithEnvironment} from "./WithEnvironment.s.sol";
import {WithSalts} from "../salts/WithSalts.s.sol";

// axis-core
import {Keycode, keycodeFromVeecode} from "@axis-core-1.0.0/modules/Keycode.sol";
import {Module} from "@axis-core-1.0.0/modules/Modules.sol";
import {AtomicAuctionHouse} from "@axis-core-1.0.0/AtomicAuctionHouse.sol";
import {BatchAuctionHouse} from "@axis-core-1.0.0/BatchAuctionHouse.sol";
import {IFeeManager} from "@axis-core-1.0.0/interfaces/IFeeManager.sol";
import {Callbacks} from "@axis-core-1.0.0/lib/Callbacks.sol";

// Uniswap
import {IUniswapV2Router02} from "@uniswap-v2-periphery-1.0.1/interfaces/IUniswapV2Router02.sol";
import {GUniFactory} from "@g-uni-v1-core-0.9.9/GUniFactory.sol";

// Callbacks
import {UniswapV2DirectToLiquidity} from "../../src/callbacks/liquidity/UniswapV2DTL.sol";
import {UniswapV3DirectToLiquidity} from "../../src/callbacks/liquidity/UniswapV3DTL.sol";
import {CappedMerkleAllowlist} from "../../src/callbacks/allowlists/CappedMerkleAllowlist.sol";
import {MerkleAllowlist} from "../../src/callbacks/allowlists/MerkleAllowlist.sol";
import {TokenAllowlist} from "../../src/callbacks/allowlists/TokenAllowlist.sol";
import {AllocatedMerkleAllowlist} from "../../src/callbacks/allowlists/AllocatedMerkleAllowlist.sol";
import {BALwithAllowlist} from "../../src/callbacks/liquidity/BaselineV2/BALwithAllowlist.sol";
import {BALwithAllocatedAllowlist} from
    "../../src/callbacks/liquidity/BaselineV2/BALwithAllocatedAllowlist.sol";
import {BALwithCappedAllowlist} from
    "../../src/callbacks/liquidity/BaselineV2/BALwithCappedAllowlist.sol";
import {BALwithTokenAllowlist} from
    "../../src/callbacks/liquidity/BaselineV2/BALwithTokenAllowlist.sol";

// Baseline
import {
    Kernel as BaselineKernel,
    Actions as BaselineKernelActions
} from "../../src/callbacks/liquidity/BaselineV2/lib/Kernel.sol";

/// @notice Declarative deployment script that reads a deployment sequence (with constructor args)
///         and a configured environment file to deploy and install contracts in the Axis protocol.
contract Deploy is Script, WithEnvironment, WithSalts {
    using stdJson for string;

    string internal constant _PREFIX_DEPLOYMENT_ROOT = "deployments";
    string internal constant _PREFIX_CALLBACKS = "deployments.callbacks";
    string internal constant _PREFIX_AUCTION_MODULES = "deployments.auctionModules";
    string internal constant _PREFIX_DERIVATIVE_MODULES = "deployments.derivativeModules";

    bytes internal constant _ATOMIC_AUCTION_HOUSE_NAME = "AtomicAuctionHouse";
    bytes internal constant _BATCH_AUCTION_HOUSE_NAME = "BatchAuctionHouse";
    bytes internal constant _BLAST_ATOMIC_AUCTION_HOUSE_NAME = "BlastAtomicAuctionHouse";
    bytes internal constant _BLAST_BATCH_AUCTION_HOUSE_NAME = "BlastBatchAuctionHouse";

    // Deploy system storage
    string internal _sequenceJson;
    mapping(string => bytes) public argsMap;
    mapping(string => bool) public installAtomicAuctionHouseMap;
    mapping(string => bool) public installBatchAuctionHouseMap;
    mapping(string => uint48[2]) public maxFeesMap; // [maxReferrerFee, maxCuratorFee]
    string[] public deployments;

    string[] public deployedToKeys;
    mapping(string => address) public deployedTo;

    // ========== DEPLOY SYSTEM FUNCTIONS ========== //

    function _setUp(string calldata chain_, string calldata deployFilePath_) internal virtual {
        _loadEnv(chain_);

        // Load deployment data
        _sequenceJson = vm.readFile(deployFilePath_);

        // Parse deployment sequence and names
        bytes memory sequence = abi.decode(_sequenceJson.parseRaw(".sequence"), (bytes));
        uint256 len = sequence.length;
        console2.log("Contracts to be deployed:", len);

        if (len == 0) {
            return;
        } else if (len == 1) {
            // Only one deployment
            string memory name = abi.decode(_sequenceJson.parseRaw(".sequence..name"), (string));
            deployments.push(name);

            _configureDeployment(_sequenceJson, name);
        } else {
            // More than one deployment
            string[] memory names =
                abi.decode(_sequenceJson.parseRaw(".sequence..name"), (string[]));
            for (uint256 i = 0; i < len; i++) {
                string memory name = names[i];
                deployments.push(name);

                _configureDeployment(_sequenceJson, name);
            }
        }
    }

    function deploy(
        string calldata chain_,
        string calldata deployFilePath_,
        bool saveDeployment
    ) external {
        // Setup
        _setUp(chain_, deployFilePath_);

        // Check that deployments is not empty
        uint256 len = deployments.length;
        require(len > 0, "No deployments");

        // Iterate through deployments
        for (uint256 i; i < len; i++) {
            // Get deploy deploy args from contract name
            string memory name = deployments[i];
            // e.g. a deployment named EncryptedMarginalPrice would require the following function: deployEncryptedMarginalPrice(string memory)
            bytes4 selector = bytes4(keccak256(bytes(string.concat("deploy", name, "(string)"))));

            console2.log("");
            console2.log("Deploying ", name);

            // Call the deploy function for the contract
            (bool success, bytes memory data) =
                address(this).call(abi.encodeWithSelector(selector, name));
            require(success, string.concat("Failed to deploy ", deployments[i]));

            // Store the deployed contract address for logging
            (address deploymentAddress, string memory keyPrefix, string memory deploymentKey) =
                abi.decode(data, (address, string, string));
            // e.g. "callbacks.EncryptedMarginalPrice"
            // The deployment functions allow the deployment key to be overridden by the sequence or arguments
            string memory deployedToKey = string.concat(keyPrefix, ".", deploymentKey);

            deployedToKeys.push(deployedToKey);
            deployedTo[deployedToKey] = deploymentAddress;

            // If required, install in the AtomicAuctionHouse and initialize max fees
            // For this to work, the deployer address must be the same as the owner of the AuctionHouse (`_envOwner`)
            if (installAtomicAuctionHouseMap[name]) {
                Module module = Module(deploymentAddress);

                console2.log("");
                AtomicAuctionHouse atomicAuctionHouse =
                    AtomicAuctionHouse(_getAddressNotZero("deployments.AtomicAuctionHouse"));

                console2.log("");
                console2.log("    Installing in AtomicAuctionHouse");
                vm.broadcast();
                atomicAuctionHouse.installModule(module);

                // Check if module is an auction module, if so, set max fees if required
                if (module.TYPE() == Module.Type.Auction) {
                    // Get keycode
                    Keycode keycode = keycodeFromVeecode(module.VEECODE());

                    // If required, set max fees
                    uint48[2] memory maxFees = maxFeesMap[name];
                    if (maxFees[0] != 0 || maxFees[1] != 0) {
                        console2.log("");
                        console2.log("    Setting max fees");
                        vm.broadcast();
                        atomicAuctionHouse.setFee(
                            keycode, IFeeManager.FeeType.MaxReferrer, maxFees[0]
                        );

                        vm.broadcast();
                        atomicAuctionHouse.setFee(
                            keycode, IFeeManager.FeeType.MaxCurator, maxFees[1]
                        );
                    }
                }
            }

            // If required, install in the BatchAuctionHouse
            // For this to work, the deployer address must be the same as the owner of the AuctionHouse (`_envOwner`)
            if (installBatchAuctionHouseMap[name]) {
                Module module = Module(deploymentAddress);

                console2.log("");
                BatchAuctionHouse batchAuctionHouse =
                    BatchAuctionHouse(_getAddressNotZero("deployments.BatchAuctionHouse"));

                console2.log("");
                console2.log("    Installing in BatchAuctionHouse");
                vm.broadcast();
                batchAuctionHouse.installModule(module);

                // Check if module is an auction module, if so, set max fees if required
                if (module.TYPE() == Module.Type.Auction) {
                    // Get keycode
                    Keycode keycode = keycodeFromVeecode(module.VEECODE());

                    // If required, set max fees
                    uint48[2] memory maxFees = maxFeesMap[name];
                    if (maxFees[0] != 0 || maxFees[1] != 0) {
                        console2.log("");
                        console2.log("    Setting max fees");
                        vm.broadcast();
                        batchAuctionHouse.setFee(
                            keycode, IFeeManager.FeeType.MaxReferrer, maxFees[0]
                        );

                        vm.broadcast();
                        batchAuctionHouse.setFee(
                            keycode, IFeeManager.FeeType.MaxCurator, maxFees[1]
                        );
                    }
                }
            }
        }

        // Save deployments to file
        if (saveDeployment) _saveDeployment(chain_);
    }

    function _saveDeployment(string memory chain_) internal {
        // Create the deployments folder if it doesn't exist
        if (!vm.isDir("./deployments")) {
            console2.log("Creating deployments directory");

            string[] memory inputs = new string[](2);
            inputs[0] = "mkdir";
            inputs[1] = "deployments";

            vm.ffi(inputs);
        }

        // Create file path
        string memory file =
            string.concat("./deployments/", ".", chain_, "-", vm.toString(block.timestamp), ".json");
        console2.log("Writing deployments to", file);

        // Write deployment info to file in JSON format
        vm.writeLine(file, "{");

        // Iterate through the contracts that were deployed and write their addresses to the file
        uint256 len = deployedToKeys.length;
        for (uint256 i; i < len - 1; ++i) {
            vm.writeLine(
                file,
                string.concat(
                    "\"",
                    deployedToKeys[i],
                    "\": \"",
                    vm.toString(deployedTo[deployedToKeys[i]]),
                    "\","
                )
            );
        }
        // Write last deployment without a comma
        vm.writeLine(
            file,
            string.concat(
                "\"",
                deployedToKeys[len - 1],
                "\": \"",
                vm.toString(deployedTo[deployedToKeys[len - 1]]),
                "\""
            )
        );
        vm.writeLine(file, "}");

        // Update the env.json file
        for (uint256 i; i < len; ++i) {
            string memory key = deployedToKeys[i];
            address value = deployedTo[key];

            string[] memory inputs = new string[](3);
            inputs[0] = "./script/deploy/write_deployment.sh";
            inputs[1] = string.concat("current", ".", chain_, ".", key);
            inputs[2] = vm.toString(value);

            vm.ffi(inputs);
        }
    }

    // ========== DEPLOYMENTS ========== //

    function deployAtomicUniswapV2DirectToLiquidity(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
        address uniswapV2Factory =
            _getEnvAddressOrOverride("constants.uniswapV2.factory", sequenceName_, "args.factory");
        address uniswapV2Router =
            _getEnvAddressOrOverride("constants.uniswapV2.router", sequenceName_, "args.router");
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);

        // Check that the router and factory match
        require(
            IUniswapV2Router02(uniswapV2Router).factory() == uniswapV2Factory,
            "UniswapV2Router.factory() does not match given Uniswap V2 factory address"
        );

        // Get the salt
        bytes32 salt_ = _getSalt(
            sequenceName_,
            type(UniswapV2DirectToLiquidity).creationCode,
            abi.encode(atomicAuctionHouse, uniswapV2Factory, uniswapV2Router)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        UniswapV2DirectToLiquidity cbAtomicUniswapV2Dtl = new UniswapV2DirectToLiquidity{
            salt: salt_
        }(atomicAuctionHouse, uniswapV2Factory, uniswapV2Router);
        console2.log("");
        console2.log("    deployed at:", address(cbAtomicUniswapV2Dtl));

        return (address(cbAtomicUniswapV2Dtl), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployBatchUniswapV2DirectToLiquidity(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        address uniswapV2Factory =
            _getEnvAddressOrOverride("constants.uniswapV2.factory", sequenceName_, "args.factory");
        address uniswapV2Router =
            _getEnvAddressOrOverride("constants.uniswapV2.router", sequenceName_, "args.router");
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);

        // Check that the router and factory match
        require(
            IUniswapV2Router02(uniswapV2Router).factory() == uniswapV2Factory,
            "UniswapV2Router.factory() does not match given Uniswap V2 factory address"
        );

        // Get the salt
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(UniswapV2DirectToLiquidity).creationCode,
            abi.encode(batchAuctionHouse, uniswapV2Factory, uniswapV2Router)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        UniswapV2DirectToLiquidity cbBatchUniswapV2Dtl = new UniswapV2DirectToLiquidity{salt: salt_}(
            batchAuctionHouse, uniswapV2Factory, uniswapV2Router
        );
        console2.log("");
        console2.log("    deployed at:", address(cbBatchUniswapV2Dtl));

        return (address(cbBatchUniswapV2Dtl), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployAtomicUniswapV3DirectToLiquidity(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
        address uniswapV3Factory = _getEnvAddressOrOverride(
            "constants.uniswapV3.factory", sequenceName_, "args.uniswapV3Factory"
        );
        address gUniFactory =
            _getEnvAddressOrOverride("constants.gUni.factory", sequenceName_, "args.gUniFactory");
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);

        // Check that the GUni factory and Uniswap V3 factory are consistent
        require(
            GUniFactory(gUniFactory).factory() == uniswapV3Factory,
            "GUniFactory.factory() does not match given Uniswap V3 factory address"
        );

        // Get the salt
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(UniswapV3DirectToLiquidity).creationCode,
            abi.encode(atomicAuctionHouse, uniswapV3Factory, gUniFactory)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        UniswapV3DirectToLiquidity cbAtomicUniswapV3Dtl = new UniswapV3DirectToLiquidity{
            salt: salt_
        }(atomicAuctionHouse, uniswapV3Factory, gUniFactory);
        console2.log("");
        console2.log("    deployed at:", address(cbAtomicUniswapV3Dtl));

        return (address(cbAtomicUniswapV3Dtl), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployBatchUniswapV3DirectToLiquidity(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        address uniswapV3Factory = _getEnvAddressOrOverride(
            "constants.uniswapV3.factory", sequenceName_, "args.uniswapV3Factory"
        );
        address gUniFactory =
            _getEnvAddressOrOverride("constants.gUni.factory", sequenceName_, "args.gUniFactory");
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);

        // Check that the GUni factory and Uniswap V3 factory are consistent
        require(
            GUniFactory(gUniFactory).factory() == uniswapV3Factory,
            "GUniFactory.factory() does not match given Uniswap V3 factory address"
        );

        // Get the salt
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(UniswapV3DirectToLiquidity).creationCode,
            abi.encode(batchAuctionHouse, uniswapV3Factory, gUniFactory)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        UniswapV3DirectToLiquidity cbBatchUniswapV3Dtl = new UniswapV3DirectToLiquidity{salt: salt_}(
            batchAuctionHouse, uniswapV3Factory, gUniFactory
        );
        console2.log("");
        console2.log("    deployed at:", address(cbBatchUniswapV3Dtl));

        return (address(cbBatchUniswapV3Dtl), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployAtomicCappedMerkleAllowlist(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(CappedMerkleAllowlist).creationCode,
            abi.encode(atomicAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        CappedMerkleAllowlist cbAtomicCappedMerkleAllowlist =
            new CappedMerkleAllowlist{salt: salt_}(atomicAuctionHouse, permissions);
        console2.log("");
        console2.log("    deployed at:", address(cbAtomicCappedMerkleAllowlist));

        return (address(cbAtomicCappedMerkleAllowlist), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployBatchCappedMerkleAllowlist(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(CappedMerkleAllowlist).creationCode,
            abi.encode(batchAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        CappedMerkleAllowlist cbBatchCappedMerkleAllowlist =
            new CappedMerkleAllowlist{salt: salt_}(batchAuctionHouse, permissions);
        console2.log("");
        console2.log("    deployed at:", address(cbBatchCappedMerkleAllowlist));

        return (address(cbBatchCappedMerkleAllowlist), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployAtomicMerkleAllowlist(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(MerkleAllowlist).creationCode,
            abi.encode(atomicAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        MerkleAllowlist cbAtomicMerkleAllowlist =
            new MerkleAllowlist{salt: salt_}(atomicAuctionHouse, permissions);
        console2.log("");
        console2.log("    deployed at:", address(cbAtomicMerkleAllowlist));

        return (address(cbAtomicMerkleAllowlist), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployBatchMerkleAllowlist(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(MerkleAllowlist).creationCode,
            abi.encode(batchAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        MerkleAllowlist cbBatchMerkleAllowlist =
            new MerkleAllowlist{salt: salt_}(batchAuctionHouse, permissions);
        console2.log("");
        console2.log("    deployed at:", address(cbBatchMerkleAllowlist));

        return (address(cbBatchMerkleAllowlist), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployAtomicTokenAllowlist(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(TokenAllowlist).creationCode,
            abi.encode(atomicAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        TokenAllowlist cbAtomicTokenAllowlist =
            new TokenAllowlist{salt: salt_}(atomicAuctionHouse, permissions);
        console2.log("");
        console2.log("    deployed at:", address(cbAtomicTokenAllowlist));

        return (address(cbAtomicTokenAllowlist), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployBatchTokenAllowlist(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(TokenAllowlist).creationCode,
            abi.encode(batchAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        TokenAllowlist cbBatchTokenAllowlist =
            new TokenAllowlist{salt: salt_}(batchAuctionHouse, permissions);
        console2.log("");
        console2.log("    deployed at:", address(cbBatchTokenAllowlist));

        return (address(cbBatchTokenAllowlist), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployAtomicAllocatedMerkleAllowlist(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(AllocatedMerkleAllowlist).creationCode,
            abi.encode(atomicAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        AllocatedMerkleAllowlist cbAtomicAllocatedMerkleAllowlist =
            new AllocatedMerkleAllowlist{salt: salt_}(atomicAuctionHouse, permissions);
        console2.log("");
        console2.log("    deployed at:", address(cbAtomicAllocatedMerkleAllowlist));

        return (address(cbAtomicAllocatedMerkleAllowlist), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployBatchAllocatedMerkleAllowlist(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: true,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });

        // Get the salt
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(AllocatedMerkleAllowlist).creationCode,
            abi.encode(batchAuctionHouse, permissions)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        AllocatedMerkleAllowlist cbBatchAllocatedMerkleAllowlist =
            new AllocatedMerkleAllowlist{salt: salt_}(batchAuctionHouse, permissions);
        console2.log("");
        console2.log("    deployed at:", address(cbBatchAllocatedMerkleAllowlist));

        return (address(cbBatchAllocatedMerkleAllowlist), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployBatchBaselineAllocatedAllowlist(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        address baselineKernel = _getSequenceAddress(sequenceName_, "args.baselineKernel");
        console2.log("    baselineKernel:", baselineKernel);
        address baselineOwner = _getSequenceAddress(sequenceName_, "args.baselineOwner");
        console2.log("    baselineOwner:", baselineOwner);
        address reserveToken = _getSequenceAddress(sequenceName_, "args.reserveToken");
        console2.log("    reserveToken:", reserveToken);
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);

        // Validate arguments
        require(baselineKernel != address(0), "baselineKernel not set");
        require(baselineOwner != address(0), "baselineOwner not set");
        require(reserveToken != address(0), "reserveToken not set");

        // Get the salt
        // This supports an arbitrary salt key, which can be set in the deployment sequence
        // This is required as each callback is single-use
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(BALwithAllocatedAllowlist).creationCode,
            abi.encode(batchAuctionHouse, baselineKernel, reserveToken, baselineOwner)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        BALwithAllocatedAllowlist batchAllowlist = new BALwithAllocatedAllowlist{salt: salt_}(
            batchAuctionHouse, baselineKernel, reserveToken, baselineOwner
        );
        console2.log("");
        console2.log("    deployed at:", address(batchAllowlist));

        // Install the module as a policy in the Baseline kernel
        vm.broadcast();
        BaselineKernel(baselineKernel).executeAction(
            BaselineKernelActions.ActivatePolicy, address(batchAllowlist)
        );

        console2.log("    Policy activated in Baseline Kernel");

        return (address(batchAllowlist), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployBatchBaselineAllowlist(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        address baselineKernel = _getSequenceAddress(sequenceName_, "args.baselineKernel");
        console2.log("    baselineKernel:", baselineKernel);
        address baselineOwner = _getSequenceAddress(sequenceName_, "args.baselineOwner");
        console2.log("    baselineOwner:", baselineOwner);
        address reserveToken = _getSequenceAddress(sequenceName_, "args.reserveToken");
        console2.log("    reserveToken:", reserveToken);
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);

        // Validate arguments
        require(baselineKernel != address(0), "baselineKernel not set");
        require(baselineOwner != address(0), "baselineOwner not set");
        require(reserveToken != address(0), "reserveToken not set");

        // Get the salt
        // This supports an arbitrary salt key, which can be set in the deployment sequence
        // This is required as each callback is single-use
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(BALwithAllowlist).creationCode,
            abi.encode(batchAuctionHouse, baselineKernel, reserveToken, baselineOwner)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        BALwithAllowlist batchAllowlist = new BALwithAllowlist{salt: salt_}(
            batchAuctionHouse, baselineKernel, reserveToken, baselineOwner
        );
        console2.log("");
        console2.log("    deployed at:", address(batchAllowlist));

        // Install the module as a policy in the Baseline kernel
        vm.broadcast();
        BaselineKernel(baselineKernel).executeAction(
            BaselineKernelActions.ActivatePolicy, address(batchAllowlist)
        );

        console2.log("    Policy activated in Baseline Kernel");

        return (address(batchAllowlist), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployBatchBaselineCappedAllowlist(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        address baselineKernel = _getSequenceAddress(sequenceName_, "args.baselineKernel");
        console2.log("    baselineKernel:", baselineKernel);
        address baselineOwner = _getSequenceAddress(sequenceName_, "args.baselineOwner");
        console2.log("    baselineOwner:", baselineOwner);
        address reserveToken = _getSequenceAddress(sequenceName_, "args.reserveToken");
        console2.log("    reserveToken:", reserveToken);
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);

        // Validate arguments
        require(baselineKernel != address(0), "baselineKernel not set");
        require(baselineOwner != address(0), "baselineOwner not set");
        require(reserveToken != address(0), "reserveToken not set");

        // Get the salt
        // This supports an arbitrary salt key, which can be set in the deployment sequence
        // This is required as each callback is single-use
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(BALwithCappedAllowlist).creationCode,
            abi.encode(batchAuctionHouse, baselineKernel, reserveToken, baselineOwner)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        BALwithCappedAllowlist batchAllowlist = new BALwithCappedAllowlist{salt: salt_}(
            batchAuctionHouse, baselineKernel, reserveToken, baselineOwner
        );
        console2.log("");
        console2.log("    deployed at:", address(batchAllowlist));

        // Install the module as a policy in the Baseline kernel
        vm.broadcast();
        BaselineKernel(baselineKernel).executeAction(
            BaselineKernelActions.ActivatePolicy, address(batchAllowlist)
        );

        console2.log("    Policy activated in Baseline Kernel");

        return (address(batchAllowlist), _PREFIX_CALLBACKS, deploymentKey);
    }

    function deployBatchBaselineTokenAllowlist(string memory sequenceName_)
        public
        returns (address, string memory, string memory)
    {
        // Get configuration variables
        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        address baselineKernel = _getSequenceAddress(sequenceName_, "args.baselineKernel");
        console2.log("    baselineKernel:", baselineKernel);
        address baselineOwner = _getSequenceAddress(sequenceName_, "args.baselineOwner");
        console2.log("    baselineOwner:", baselineOwner);
        address reserveToken = _getSequenceAddress(sequenceName_, "args.reserveToken");
        console2.log("    reserveToken:", reserveToken);
        string memory deploymentKey = _getDeploymentKey(sequenceName_);
        console2.log("    deploymentKey:", deploymentKey);

        // Validate arguments
        require(baselineKernel != address(0), "baselineKernel not set");
        require(baselineOwner != address(0), "baselineOwner not set");
        require(reserveToken != address(0), "reserveToken not set");

        // Get the salt
        // This supports an arbitrary salt key, which can be set in the deployment sequence
        // This is required as each callback is single-use
        bytes32 salt_ = _getSalt(
            deploymentKey,
            type(BALwithTokenAllowlist).creationCode,
            abi.encode(batchAuctionHouse, baselineKernel, reserveToken, baselineOwner)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        BALwithTokenAllowlist batchAllowlist = new BALwithTokenAllowlist{salt: salt_}(
            batchAuctionHouse, baselineKernel, reserveToken, baselineOwner
        );
        console2.log("");
        console2.log("    deployed at:", address(batchAllowlist));

        // Install the module as a policy in the Baseline kernel
        vm.broadcast();
        BaselineKernel(baselineKernel).executeAction(
            BaselineKernelActions.ActivatePolicy, address(batchAllowlist)
        );

        console2.log("    Policy activated in Baseline Kernel");

        return (address(batchAllowlist), _PREFIX_CALLBACKS, deploymentKey);
    }

    // ========== HELPER FUNCTIONS ========== //

    function _configureDeployment(string memory data_, string memory name_) internal {
        console2.log("");
        console2.log("    Configuring", name_);

        // Check if it should be installed in the AtomicAuctionHouse
        if (
            _sequenceKeyExists(name_, "installAtomicAuctionHouse")
                && _getSequenceBool(name_, "installAtomicAuctionHouse")
        ) {
            installAtomicAuctionHouseMap[name_] = true;
            console2.log("    Queueing for installation in AtomicAuctionHouse");
        } else {
            console2.log("    Skipping installation in AtomicAuctionHouse");
        }

        // Check if it should be installed in the BatchAuctionHouse
        if (
            _sequenceKeyExists(name_, "installBatchAuctionHouse")
                && _getSequenceBool(name_, "installBatchAuctionHouse")
        ) {
            installBatchAuctionHouseMap[name_] = true;
            console2.log("    Queueing for installation in BatchAuctionHouse");
        } else {
            console2.log("    Skipping installation in BatchAuctionHouse");
        }

        // Check if max fees need to be initialized
        uint48[2] memory maxFees;
        bytes memory maxReferrerFee = _readDataValue(data_, name_, "maxReferrerFee");
        bytes memory maxCuratorFee = _readDataValue(data_, name_, "maxCuratorFee");
        maxFees[0] = maxReferrerFee.length > 0
            ? abi.decode(_readDataValue(data_, name_, "maxReferrerFee"), (uint48))
            : 0;
        maxFees[1] = maxCuratorFee.length > 0
            ? abi.decode(_readDataValue(data_, name_, "maxCuratorFee"), (uint48))
            : 0;

        if (maxFees[0] != 0 || maxFees[1] != 0) {
            maxFeesMap[name_] = maxFees;
        }
    }

    /// @notice Get an address for a given key
    /// @dev    This variant will first check for the key in the
    ///         addresses from the current deployment sequence (stored in `deployedTo`),
    ///         followed by the contents of `env.json`.
    ///
    ///         If no value is found for the key, or it is the zero address, the function will revert.
    ///
    /// @param  key_    Key to look for
    /// @return address Returns the address
    function _getAddressNotZero(string memory key_) internal view returns (address) {
        // Get from the deployed addresses first
        address deployedAddress = deployedTo[key_];

        if (deployedAddress != address(0)) {
            console2.log("    %s: %s (from deployment addresses)", key_, deployedAddress);
            return deployedAddress;
        }

        return _envAddressNotZero(key_);
    }

    function _getDeploymentKey(string memory sequenceName_) internal view returns (string memory) {
        return string.concat(
            sequenceName_, _getSequenceStringOrFallback(sequenceName_, "deploymentKeySuffix", "")
        );
    }

    /// @notice Construct a key to access a value in the deployment sequence
    function _getSequenceKey(
        string memory name_,
        string memory key_
    ) internal pure returns (string memory) {
        return string.concat(".sequence[?(@.name == '", name_, "')].", key_);
    }

    /// @notice Determines if a key exists in the deployment sequence
    function _sequenceKeyExists(
        string memory name_,
        string memory key_
    ) internal view returns (bool) {
        return vm.keyExists(_sequenceJson, _getSequenceKey(name_, key_));
    }

    /// @notice Obtains a string value from the given key in the deployment sequence
    /// @dev    This will revert if the key does not exist
    function _getSequenceString(
        string memory name_,
        string memory key_
    ) internal view returns (string memory) {
        return vm.parseJsonString(_sequenceJson, _getSequenceKey(name_, key_));
    }

    /// @notice Obtains an address value from the given key in the deployment sequence
    /// @dev    This will revert if the key does not exist
    function _getSequenceAddress(
        string memory name_,
        string memory key_
    ) internal view returns (address) {
        return vm.parseJsonAddress(_sequenceJson, _getSequenceKey(name_, key_));
    }

    /// @notice Obtains an bool value from the given key in the deployment sequence
    /// @dev    This will revert if the key does not exist
    function _getSequenceBool(
        string memory name_,
        string memory key_
    ) internal view returns (bool) {
        return vm.parseJsonBool(_sequenceJson, _getSequenceKey(name_, key_));
    }

    /// @notice Obtains an address value from the deployment sequence (if it exists), or the env.json as a fallback
    function _getEnvAddressOrOverride(
        string memory envKey_,
        string memory sequenceName_,
        string memory key_
    ) internal view returns (address) {
        // Check if the key is set in the deployment sequence
        if (_sequenceKeyExists(sequenceName_, key_)) {
            address sequenceAddress = _getSequenceAddress(sequenceName_, key_);
            console2.log("    %s: %s (from deployment sequence)", envKey_, sequenceAddress);
            return sequenceAddress;
        }

        // Otherwsie return from the environment variables
        return _envAddressNotZero(envKey_);
    }

    /// @notice Obtains a string value from the deployment sequence (if it exists), or a fallback value
    function _getSequenceStringOrFallback(
        string memory name_,
        string memory key_,
        string memory fallbackValue_
    ) internal view returns (string memory) {
        // Check if the key is set in the deployment sequence
        if (_sequenceKeyExists(name_, key_)) {
            return _getSequenceString(name_, key_);
        }

        // Otherwise, return the fallback value
        return fallbackValue_;
    }

    /// @notice Reads a raw bytes value from the deployment sequence
    function _readDataValue(
        string memory data_,
        string memory name_,
        string memory key_
    ) internal pure returns (bytes memory) {
        // This will return "0x" if the key doesn't exist
        return data_.parseRaw(_getSequenceKey(name_, key_));
    }
}
