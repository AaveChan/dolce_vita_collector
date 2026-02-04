// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPool {
    function mintToTreasury(address[] calldata assets) external;
    function getReserveData(address asset) external view returns (ReserveData memory);
}

struct ReserveData {
    uint256 configuration;
    uint128 liquidityIndex;
    uint128 currentLiquidityRate;
    uint128 variableBorrowIndex;
    uint128 currentVariableBorrowRate;
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    uint16 id;
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint128 accruedToTreasury;
    uint128 unbacked;
    uint128 isolationModeTotalDebt;
}

contract MintToTreasuryScript is Script {
    mapping(string => address) pools;
    mapping(string => string) rpcUrls;
    string[] networkNames = [
        "MAINNET", "AVALANCHE", "OPTIMISM", "POLYGON",
        "ARBITRUM", "BASE", "GNOSIS", "BNB", "SCROLL", "METIS",
        "LINEA", "SONIC", "CELO", "PLASMA", "SONEIUM",
        "MANTLE", "MEGAETH", "INK"
    ];
    string constant RESERVES_PATH = "./logs/reserves.json";

    function setUp() public {
        for (uint i = 0; i < networkNames.length; i++) {
            string memory networkName = networkNames[i];
            string memory poolEnvVar = string(abi.encodePacked(networkName, "_MAIN_POOL"));
            string memory rpcEnvVar = string(abi.encodePacked("RPC_", networkName));
            
            pools[networkName] = vm.envAddress(poolEnvVar);
            rpcUrls[networkName] = vm.envString(rpcEnvVar);
        }
        // Special cases for MAINNET_LIDO_POOL and MAINNET_ETHERFI_POOL
        pools["MAINNET_LIDO"] = vm.envAddress("MAINNET_LIDO_POOL");
        pools["MAINNET_ETHERFI"] = vm.envAddress("MAINNET_ETHERFI_POOL");
        pools["MAINNET_HORIZON"] = vm.envAddress("MAINNET_HORIZON_POOL");
    }

    function run() public {
        string memory targetNetwork = vm.envOr("TARGET_NETWORK", string(""));
        if (bytes(targetNetwork).length > 0) {
            runForNetwork(targetNetwork);
        } else {
            runForAllNetworks();
        }
    }

    function runForNetwork(string memory networkName) internal {
        require(pools[networkName] != address(0), "Invalid network name");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork(rpcUrls[networkName]);
        vm.startBroadcast(deployerPrivateKey);
        
        mintToTreasuryForPool(networkName, "MAIN", pools[networkName]);
        
        if (keccak256(abi.encodePacked(networkName)) == keccak256(abi.encodePacked("MAINNET"))) {
            mintToTreasuryForPool("MAINNET", "LIDO", pools["MAINNET_LIDO"]);
            mintToTreasuryForPool("MAINNET", "ETHERFI", pools["MAINNET_ETHERFI"]);
            mintToTreasuryForPool("MAINNET", "HORIZON", pools["MAINNET_HORIZON"]);
        }
        
        vm.stopBroadcast();
    }

    function runForAllNetworks() internal {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        for (uint i = 0; i < networkNames.length; i++) {
            string memory networkName = networkNames[i];
            vm.createSelectFork(rpcUrls[networkName]);
            vm.startBroadcast(deployerPrivateKey);
            
            mintToTreasuryForPool(networkName, "MAIN", pools[networkName]);
            
            if (keccak256(abi.encodePacked(networkName)) == keccak256(abi.encodePacked("MAINNET"))) {
                mintToTreasuryForPool("MAINNET", "LIDO", pools["MAINNET_LIDO"]);
                mintToTreasuryForPool("MAINNET", "ETHERFI", pools["MAINNET_ETHERFI"]);
                mintToTreasuryForPool("MAINNET", "HORIZON", pools["MAINNET_HORIZON"]);
            }
            
            vm.stopBroadcast();
        }
    }

    function mintToTreasuryForPool(string memory network, string memory poolType, address poolAddress) internal {
        address[] memory reserves = getReservesForPool(network, poolType);
        if (reserves.length == 0) {
            console.log("Skipping %s %s: no reserves", network, poolType);
            return;
        }

        // Filter to only reserves with accrued interest
        address[] memory reservesWithAccrued = new address[](reserves.length);
        uint256 count = 0;
        uint256 totalAccrued = 0;

        for (uint256 i = 0; i < reserves.length; i++) {
            ReserveData memory data = IPool(poolAddress).getReserveData(reserves[i]);
            if (data.accruedToTreasury > 0) {
                reservesWithAccrued[count] = reserves[i];
                totalAccrued += data.accruedToTreasury;
                count++;
            }
        }

        if (count == 0) {
            console.log("Skipping %s %s: no accrued interest", network, poolType);
            return;
        }

        // Resize array to actual count
        address[] memory finalReserves = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            finalReserves[i] = reservesWithAccrued[i];
        }

        console.log("Minting %s %s: %d reserves with accrued interest", network, poolType, count);
        IPool(poolAddress).mintToTreasury(finalReserves);
    }

    function getReservesForPool(string memory network, string memory poolType) internal view returns (address[] memory) {
        string memory json = vm.readFile(RESERVES_PATH);
        string memory path = string(abi.encodePacked(".", network, ".", poolType));

        // Check if key exists before parsing
        if (!vm.keyExistsJson(json, path)) {
            return new address[](0);
        }

        bytes memory parseJson = vm.parseJson(json, path);
        if (parseJson.length == 0) {
            return new address[](0);
        }

        return abi.decode(parseJson, (address[]));
    }
}