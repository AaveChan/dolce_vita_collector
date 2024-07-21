// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPool {
    function getReservesList() external view returns (address[] memory);
}

struct NetworkConfig {
    string name;
    string[] poolNames;
}

contract FetchReservesScript is Script {
    function setUp() public {}

    function run() public {
        NetworkConfig[] memory networks = getNetworkConfigs();

        string memory jsonOutput = "{";
        string memory logContent = "";
        bool isFirstNetwork = true;

        for (uint i = 0; i < networks.length; i++) {
            NetworkConfig memory network = networks[i];
            string memory rpc = vm.envString(string(abi.encodePacked("RPC_", network.name)));
            
            if (!isFirstNetwork) jsonOutput = string(abi.encodePacked(jsonOutput, ","));
            isFirstNetwork = false;
            jsonOutput = string(abi.encodePacked(jsonOutput, '"', network.name, '":{'));

            bool isFirstPool = true;
            for (uint j = 0; j < network.poolNames.length; j++) {
                string memory poolName = network.poolNames[j];
                address poolAddress = vm.envAddress(string(abi.encodePacked(network.name, "_", poolName, "_POOL")));

                logContent = string(abi.encodePacked(logContent, "Fetching reserves for ", network.name, " ", poolName, "\n"));

                try vm.createSelectFork(rpc) returns (uint256) {
                    IPool pool = IPool(poolAddress);
                    address[] memory reserves;
                    
                    try pool.getReservesList() returns (address[] memory _reserves) {
                        reserves = _reserves;
                        if (reserves.length > 0) {
                            logContent = string(abi.encodePacked(logContent, "Successfully fetched ", vm.toString(reserves.length), " reserves for ", network.name, " ", poolName, "\n"));
                            
                            if (!isFirstPool) jsonOutput = string(abi.encodePacked(jsonOutput, ","));
                            isFirstPool = false;
                            jsonOutput = string(abi.encodePacked(jsonOutput, '"', poolName, '":['));
                            for (uint k = 0; k < reserves.length; k++) {
                                if (k > 0) jsonOutput = string(abi.encodePacked(jsonOutput, ","));
                                jsonOutput = string(abi.encodePacked(jsonOutput, '"', vm.toString(reserves[k]), '"'));
                            }
                            jsonOutput = string(abi.encodePacked(jsonOutput, "]"));
                        } else {
                            logContent = string(abi.encodePacked(logContent, "No reserves found for ", network.name, " ", poolName, ". Skipping.\n"));
                        }
                    } catch {
                        logContent = string(abi.encodePacked(logContent, "Failed to fetch reserves for ", network.name, " ", poolName, "\n"));
                    }
                } catch {
                    logContent = string(abi.encodePacked(logContent, "Failed to connect to ", network.name, " RPC\n"));
                }
            }
            jsonOutput = string(abi.encodePacked(jsonOutput, "}"));
        }

        jsonOutput = string(abi.encodePacked(jsonOutput, "}"));
        
        // Write JSON output to file
        vm.writeFile("./logs/reserves.json", jsonOutput);
        
        // Write log to file
        vm.writeFile("./logs/fetch_reserves_detail.log", logContent);
        
        console.log("Reserves fetched and written to ./logs/reserves.json");
        console.log("Detailed log written to ./logs/fetch_reserves_detail.log");
    }

    function getNetworkConfigs() internal pure returns (NetworkConfig[] memory) {
        NetworkConfig[] memory configs = new NetworkConfig[](11);
        
        string[] memory mainnetPools = new string[](2);
        mainnetPools[0] = "MAIN";
        mainnetPools[1] = "LIDO";
        configs[0] = NetworkConfig("MAINNET", mainnetPools);

        string[] memory singlePool = new string[](1);
        singlePool[0] = "MAIN";

        configs[1] = NetworkConfig("AVALANCHE", singlePool);
        configs[2] = NetworkConfig("OPTIMISM", singlePool);
        configs[3] = NetworkConfig("POLYGON", singlePool);
        configs[4] = NetworkConfig("ARBITRUM", singlePool);
        configs[5] = NetworkConfig("FANTOM", singlePool);
        configs[6] = NetworkConfig("HARMONY", singlePool);
        configs[7] = NetworkConfig("METIS", singlePool);
        configs[8] = NetworkConfig("BASE", singlePool);
        configs[9] = NetworkConfig("GNOSIS", singlePool);
        configs[10] = NetworkConfig("BNB", singlePool);

        return configs;
    }
}