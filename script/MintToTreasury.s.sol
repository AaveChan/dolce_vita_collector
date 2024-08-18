// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPool {
    function mintToTreasury(address[] calldata assets) external;
}

contract MintToTreasuryScript is Script {
    mapping(string => address) pools;
    mapping(string => string) rpcUrls;
    string[] networkNames = [
        "MAINNET", "AVALANCHE", "OPTIMISM", "POLYGON", 
        "ARBITRUM", "BASE", "GNOSIS", "BNB", "SCROLL", "METIS"
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
        // Special case for MAINNET_LIDO_POOL
        pools["MAINNET_LIDO"] = vm.envAddress("MAINNET_LIDO_POOL");
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
            }
            
            vm.stopBroadcast();
        }
    }

    function mintToTreasuryForPool(string memory network, string memory poolType, address poolAddress) internal {
        address[] memory reserves = getReservesForPool(network, poolType);
        if (reserves.length == 0) {
            return; // Skip if reserves array is empty
        }
        IPool(poolAddress).mintToTreasury(reserves);
    }

    function getReservesForPool(string memory network, string memory poolType) internal view returns (address[] memory) {
        string memory json = vm.readFile(RESERVES_PATH);
        bytes memory parseJson = vm.parseJson(json, string(abi.encodePacked(".", network, ".", poolType)));
        return abi.decode(parseJson, (address[]));
    }
}