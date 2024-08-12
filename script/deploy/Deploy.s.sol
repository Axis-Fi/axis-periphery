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
        string memory data = vm.readFile(deployFilePath_);

        // Parse deployment sequence and names
        bytes memory sequence = abi.decode(data.parseRaw(".sequence"), (bytes));
        uint256 len = sequence.length;
        console2.log("Contracts to be deployed:", len);

        if (len == 0) {
            return;
        } else if (len == 1) {
            // Only one deployment
            string memory name = abi.decode(data.parseRaw(".sequence..name"), (string));
            deployments.push(name);

            _configureDeployment(data, name);
        } else {
            // More than one deployment
            string[] memory names = abi.decode(data.parseRaw(".sequence..name"), (string[]));
            for (uint256 i = 0; i < len; i++) {
                string memory name = names[i];
                deployments.push(name);

                _configureDeployment(data, name);
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
            // e.g. a deployment named EncryptedMarginalPrice would require the following function: deployEncryptedMarginalPrice(bytes)
            bytes4 selector = bytes4(keccak256(bytes(string.concat("deploy", name, "(bytes)"))));
            bytes memory args = argsMap[name];

            // Call the deploy function for the contract
            (bool success, bytes memory data) =
                address(this).call(abi.encodeWithSelector(selector, args));
            require(success, string.concat("Failed to deploy ", deployments[i]));

            // Store the deployed contract address for logging
            (address deploymentAddress, string memory keyPrefix) =
                abi.decode(data, (address, string));
            string memory deployedToKey = string.concat(keyPrefix, ".", name);

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

    function deployAtomicUniswapV2DirectToLiquidity(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying UniswapV2DirectToLiquidity (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
        address uniswapV2Factory = _getAddressNotZero("constants.uniswapV2.factory");
        address uniswapV2Router = _getAddressNotZero("constants.uniswapV2.router");

        // Check that the router and factory match
        require(
            IUniswapV2Router02(uniswapV2Router).factory() == uniswapV2Factory,
            "UniswapV2Router.factory() does not match given Uniswap V2 factory address"
        );

        // Get the salt
        bytes32 salt_ = _getSalt(
            "UniswapV2DirectToLiquidity",
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
        console2.log(
            "    UniswapV2DirectToLiquidity (Atomic) deployed at:", address(cbAtomicUniswapV2Dtl)
        );

        return (address(cbAtomicUniswapV2Dtl), _PREFIX_CALLBACKS);
    }

    function deployBatchUniswapV2DirectToLiquidity(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying UniswapV2DirectToLiquidity (Batch)");

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        address uniswapV2Factory = _getAddressNotZero("constants.uniswapV2.factory");
        address uniswapV2Router = _getAddressNotZero("constants.uniswapV2.router");

        // Check that the router and factory match
        require(
            IUniswapV2Router02(uniswapV2Router).factory() == uniswapV2Factory,
            "UniswapV2Router.factory() does not match given Uniswap V2 factory address"
        );

        // Get the salt
        bytes32 salt_ = _getSalt(
            "UniswapV2DirectToLiquidity",
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
        console2.log(
            "    UniswapV2DirectToLiquidity (Batch) deployed at:", address(cbBatchUniswapV2Dtl)
        );

        return (address(cbBatchUniswapV2Dtl), _PREFIX_CALLBACKS);
    }

    function deployAtomicUniswapV3DirectToLiquidity(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying UniswapV3DirectToLiquidity (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
        address uniswapV3Factory = _getAddressNotZero("constants.uniswapV3.factory");
        address gUniFactory = _getAddressNotZero("constants.gUni.factory");

        // Check that the GUni factory and Uniswap V3 factory are consistent
        require(
            GUniFactory(gUniFactory).factory() == uniswapV3Factory,
            "GUniFactory.factory() does not match given Uniswap V3 factory address"
        );

        // Get the salt
        bytes32 salt_ = _getSalt(
            "UniswapV3DirectToLiquidity",
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
        console2.log(
            "    UniswapV3DirectToLiquidity (Atomic) deployed at:", address(cbAtomicUniswapV3Dtl)
        );

        return (address(cbAtomicUniswapV3Dtl), _PREFIX_CALLBACKS);
    }

    function deployBatchUniswapV3DirectToLiquidity(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying UniswapV3DirectToLiquidity (Batch)");

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
        address uniswapV3Factory = _getAddressNotZero("constants.uniswapV3.factory");
        address gUniFactory = _getAddressNotZero("constants.gUni.factory");

        // Check that the GUni factory and Uniswap V3 factory are consistent
        require(
            GUniFactory(gUniFactory).factory() == uniswapV3Factory,
            "GUniFactory.factory() does not match given Uniswap V3 factory address"
        );

        // Get the salt
        bytes32 salt_ = _getSalt(
            "UniswapV3DirectToLiquidity",
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
        console2.log(
            "    UniswapV3DirectToLiquidity (Batch) deployed at:", address(cbBatchUniswapV3Dtl)
        );

        return (address(cbBatchUniswapV3Dtl), _PREFIX_CALLBACKS);
    }

    function deployAtomicCappedMerkleAllowlist(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying CappedMerkleAllowlist (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
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
            "CappedMerkleAllowlist",
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
        console2.log(
            "    CappedMerkleAllowlist (Atomic) deployed at:",
            address(cbAtomicCappedMerkleAllowlist)
        );

        return (address(cbAtomicCappedMerkleAllowlist), _PREFIX_CALLBACKS);
    }

    function deployBatchCappedMerkleAllowlist(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying CappedMerkleAllowlist (Batch)");

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
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
            "CappedMerkleAllowlist",
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
        console2.log(
            "    CappedMerkleAllowlist (Batch) deployed at:", address(cbBatchCappedMerkleAllowlist)
        );

        return (address(cbBatchCappedMerkleAllowlist), _PREFIX_CALLBACKS);
    }

    function deployAtomicMerkleAllowlist(bytes memory) public returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying MerkleAllowlist (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
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
            "MerkleAllowlist",
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
        console2.log("    MerkleAllowlist (Atomic) deployed at:", address(cbAtomicMerkleAllowlist));

        return (address(cbAtomicMerkleAllowlist), _PREFIX_CALLBACKS);
    }

    function deployBatchMerkleAllowlist(bytes memory) public returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying MerkleAllowlist (Batch)");

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
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
            "MerkleAllowlist",
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
        console2.log("    MerkleAllowlist (Batch) deployed at:", address(cbBatchMerkleAllowlist));

        return (address(cbBatchMerkleAllowlist), _PREFIX_CALLBACKS);
    }

    function deployAtomicTokenAllowlist(bytes memory) public returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying TokenAllowlist (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
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
            "TokenAllowlist",
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
        console2.log("    TokenAllowlist (Atomic) deployed at:", address(cbAtomicTokenAllowlist));

        return (address(cbAtomicTokenAllowlist), _PREFIX_CALLBACKS);
    }

    function deployBatchTokenAllowlist(bytes memory) public returns (address, string memory) {
        // No args used
        console2.log("");
        console2.log("Deploying TokenAllowlist (Batch)");

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
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
            "TokenAllowlist",
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
        console2.log("    TokenAllowlist (Batch) deployed at:", address(cbBatchTokenAllowlist));

        return (address(cbBatchTokenAllowlist), _PREFIX_CALLBACKS);
    }

    function deployAtomicAllocatedMerkleAllowlist(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying AllocatedMerkleAllowlist (Atomic)");

        address atomicAuctionHouse = _getAddressNotZero("deployments.AtomicAuctionHouse");
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
            "AllocatedMerkleAllowlist",
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
        console2.log(
            "    AllocatedMerkleAllowlist (Atomic) deployed at:",
            address(cbAtomicAllocatedMerkleAllowlist)
        );

        return (address(cbAtomicAllocatedMerkleAllowlist), _PREFIX_CALLBACKS);
    }

    function deployBatchAllocatedMerkleAllowlist(bytes memory)
        public
        returns (address, string memory)
    {
        // No args used
        console2.log("");
        console2.log("Deploying AllocatedMerkleAllowlist (Batch)");

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");
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
            "AllocatedMerkleAllowlist",
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
        console2.log(
            "    AllocatedMerkleAllowlist (Batch) deployed at:",
            address(cbBatchAllocatedMerkleAllowlist)
        );

        return (address(cbBatchAllocatedMerkleAllowlist), _PREFIX_CALLBACKS);
    }

    function deployBatchBaselineAllocatedAllowlist(bytes memory args_)
        public
        returns (address, string memory)
    {
        // Decode arguments
        (address baselineKernel, address baselineOwner, address reserveToken) =
            abi.decode(args_, (address, address, address));

        // Validate arguments
        require(baselineKernel != address(0), "baselineKernel not set");
        require(baselineOwner != address(0), "baselineOwner not set");
        require(reserveToken != address(0), "reserveToken not set");

        console2.log("");
        console2.log("Deploying BaselineAllocatedAllowlist (Batch)");
        console2.log("    Kernel", baselineKernel);
        console2.log("    Owner", baselineOwner);
        console2.log("    ReserveToken", reserveToken);

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");

        // Get the salt
        // This supports an arbitrary salt key, which can be set in the deployment sequence
        // This is required as each callback is single-use
        bytes32 salt_ = _getSalt(
            "BaselineAllocatedAllowlist",
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
        console2.log("    BaselineAllocatedAllowlist (Batch) deployed at:", address(batchAllowlist));

        // Install the module as a policy in the Baseline kernel
        vm.broadcast();
        BaselineKernel(baselineKernel).executeAction(
            BaselineKernelActions.ActivatePolicy, address(batchAllowlist)
        );

        console2.log("    Policy activated in Baseline Kernel");

        return (address(batchAllowlist), _PREFIX_CALLBACKS);
    }

    function deployBatchBaselineAllowlist(bytes memory args_)
        public
        returns (address, string memory)
    {
        // Decode arguments
        (address baselineKernel, address baselineOwner, address reserveToken) =
            abi.decode(args_, (address, address, address));

        // Validate arguments
        require(baselineKernel != address(0), "baselineKernel not set");
        require(baselineOwner != address(0), "baselineOwner not set");
        require(reserveToken != address(0), "reserveToken not set");

        console2.log("");
        console2.log("Deploying BaselineAllowlist (Batch)");
        console2.log("    Kernel", baselineKernel);
        console2.log("    Owner", baselineOwner);
        console2.log("    ReserveToken", reserveToken);

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");

        // Get the salt
        // This supports an arbitrary salt key, which can be set in the deployment sequence
        // This is required as each callback is single-use
        bytes32 salt_ = _getSalt(
            "BaselineAllowlist",
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
        console2.log("    BaselineAllowlist (Batch) deployed at:", address(batchAllowlist));

        // Install the module as a policy in the Baseline kernel
        vm.broadcast();
        BaselineKernel(baselineKernel).executeAction(
            BaselineKernelActions.ActivatePolicy, address(batchAllowlist)
        );

        console2.log("    Policy activated in Baseline Kernel");

        return (address(batchAllowlist), _PREFIX_CALLBACKS);
    }

    function deployBatchBaselineCappedAllowlist(bytes memory args_)
        public
        returns (address, string memory)
    {
        // Decode arguments
        (address baselineKernel, address baselineOwner, address reserveToken) =
            abi.decode(args_, (address, address, address));

        // Validate arguments
        require(baselineKernel != address(0), "baselineKernel not set");
        require(baselineOwner != address(0), "baselineOwner not set");
        require(reserveToken != address(0), "reserveToken not set");

        console2.log("");
        console2.log("Deploying BaselineCappedAllowlist (Batch)");
        console2.log("    Kernel", baselineKernel);
        console2.log("    Owner", baselineOwner);
        console2.log("    ReserveToken", reserveToken);

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");

        // Get the salt
        // This supports an arbitrary salt key, which can be set in the deployment sequence
        // This is required as each callback is single-use
        bytes32 salt_ = _getSalt(
            "BaselineCappedAllowlist",
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
        console2.log("    BaselineCappedAllowlist (Batch) deployed at:", address(batchAllowlist));

        // Install the module as a policy in the Baseline kernel
        vm.broadcast();
        BaselineKernel(baselineKernel).executeAction(
            BaselineKernelActions.ActivatePolicy, address(batchAllowlist)
        );

        console2.log("    Policy activated in Baseline Kernel");

        return (address(batchAllowlist), _PREFIX_CALLBACKS);
    }

    function deployBatchBaselineTokenAllowlist(bytes memory args_)
        public
        returns (address, string memory)
    {
        // Decode arguments
        (address baselineKernel, address reserveToken) = abi.decode(args_, (address, address));

        // Validate arguments
        require(baselineKernel != address(0), "baselineKernel not set");
        require(reserveToken != address(0), "reserveToken not set");

        console2.log("");
        console2.log("Deploying BaselineTokenAllowlist (Batch)");
        console2.log("    Kernel", baselineKernel);
        console2.log("    ReserveToken", reserveToken);

        address batchAuctionHouse = _getAddressNotZero("deployments.BatchAuctionHouse");

        // Get the salt
        // This supports an arbitrary salt key, which can be set in the deployment sequence
        // This is required as each callback is single-use
        bytes32 salt_ = _getSalt(
            "BaselineTokenAllowlist",
            type(BALwithTokenAllowlist).creationCode,
            abi.encode(batchAuctionHouse, baselineKernel, reserveToken)
        );

        // Revert if the salt is not set
        require(salt_ != bytes32(0), "Salt not set");

        // Deploy the module
        console2.log("    salt:", vm.toString(salt_));

        vm.broadcast();
        BALwithTokenAllowlist batchAllowlist =
            new BALwithTokenAllowlist{salt: salt_}(batchAuctionHouse, baselineKernel, reserveToken);
        console2.log("");
        console2.log("    BaselineTokenAllowlist (Batch) deployed at:", address(batchAllowlist));

        // Install the module as a policy in the Baseline kernel
        vm.broadcast();
        BaselineKernel(baselineKernel).executeAction(
            BaselineKernelActions.ActivatePolicy, address(batchAllowlist)
        );

        console2.log("    Policy activated in Baseline Kernel");

        return (address(batchAllowlist), _PREFIX_CALLBACKS);
    }

    // ========== HELPER FUNCTIONS ========== //

    function _configureDeployment(string memory data_, string memory name_) internal {
        console2.log("    Configuring", name_);

        // Parse and store args
        // Note: constructor args need to be provided in alphabetical order
        // due to changes with forge-std or a struct needs to be used
        argsMap[name_] = _readDataValue(data_, name_, "args");

        // Check if it should be installed in the AtomicAuctionHouse
        if (_readDataBoolean(data_, name_, "installAtomicAuctionHouse")) {
            installAtomicAuctionHouseMap[name_] = true;
        }

        // Check if it should be installed in the BatchAuctionHouse
        if (_readDataBoolean(data_, name_, "installBatchAuctionHouse")) {
            installBatchAuctionHouseMap[name_] = true;
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

    function _readDataValue(
        string memory data_,
        string memory name_,
        string memory key_
    ) internal pure returns (bytes memory) {
        // This will return "0x" if the key doesn't exist
        return data_.parseRaw(string.concat(".sequence[?(@.name == '", name_, "')].", key_));
    }

    function _readStringValue(
        string memory data_,
        string memory name_,
        string memory key_
    ) internal pure returns (string memory) {
        bytes memory dataValue = _readDataValue(data_, name_, key_);

        // If the key is not set, return an empty string
        if (dataValue.length == 0) {
            return "";
        }

        return abi.decode(dataValue, (string));
    }

    function _readDataBoolean(
        string memory data_,
        string memory name_,
        string memory key_
    ) internal pure returns (bool) {
        bytes memory dataValue = _readDataValue(data_, name_, key_);

        // Comparing `bytes memory` directly doesn't work, so we need to convert to `bytes32`
        return bytes32(dataValue) == bytes32(abi.encodePacked(uint256(1)));
    }
}
