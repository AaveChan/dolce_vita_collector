// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPool {
    function getReservesList() external view returns (address[] memory);
}

/// @notice Fetches reserves for a SINGLE network (called in parallel by bash wrapper)
/// Usage: TARGET_NETWORK=MAINNET TARGET_POOLS=MAIN,LIDO forge script script/FetchReservesSingle.s.sol -vvvv
contract FetchReservesSingleScript is Script {
    function setUp() public {}

    function run() public {
        string memory networkName = vm.envString("TARGET_NETWORK");
        string memory rpc = vm.envString(string(abi.encodePacked("RPC_", networkName)));

        // Pool types auto-discovered from .env by the bash wrapper
        string[] memory poolNames = vm.envString("TARGET_POOLS", ",");

        string memory jsonOutput = "{";
        bool isFirstPool = true;

        vm.createSelectFork(rpc);

        for (uint j = 0; j < poolNames.length; j++) {
            string memory poolName = poolNames[j];
            address poolAddress = vm.envAddress(
                string(abi.encodePacked(networkName, "_", poolName, "_POOL"))
            );

            try IPool(poolAddress).getReservesList() returns (address[] memory reserves) {
                if (reserves.length > 0) {
                    if (!isFirstPool) jsonOutput = string(abi.encodePacked(jsonOutput, ","));
                    isFirstPool = false;
                    jsonOutput = string(abi.encodePacked(jsonOutput, '"', poolName, '":['));
                    for (uint k = 0; k < reserves.length; k++) {
                        if (k > 0) jsonOutput = string(abi.encodePacked(jsonOutput, ","));
                        jsonOutput = string(abi.encodePacked(jsonOutput, '"', vm.toString(reserves[k]), '"'));
                    }
                    jsonOutput = string(abi.encodePacked(jsonOutput, "]"));
                    console.log("Fetched %d reserves for %s %s", reserves.length, networkName, poolName);
                }
            } catch {
                console.log("Failed to fetch reserves for %s %s", networkName, poolName);
            }
        }

        jsonOutput = string(abi.encodePacked(jsonOutput, "}"));

        // Write per-network JSON fragment
        string memory outPath = string(abi.encodePacked("./logs/reserves_", networkName, ".json"));
        vm.writeFile(outPath, jsonOutput);
        console.log("Written to %s", outPath);
    }
}
