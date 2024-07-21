// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPool {
    function mintToTreasury(address[] calldata assets) external;
}

contract MintToTreasuryScript is Script {
    function setUp() public {}

    function run(string memory reservesJson) public {
        string memory network = vm.envString("NETWORK");
        string memory pool = vm.envString("POOL");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolAddress = vm.envAddress(string(abi.encodePacked(network, "_", pool, "_POOL")));

        string memory logContent = string(abi.encodePacked(
            "Network: ", network, "\n",
            "Pool: ", pool, "\n",
            "Pool address: ", vm.toString(poolAddress), "\n"
        ));

        // Check if the network and pool exist in the JSON
        bytes memory poolData = vm.parseJson(reservesJson, string(abi.encodePacked(".", network, ".", pool)));
        if (poolData.length == 0) {
            logContent = string(abi.encodePacked(logContent, "No reserves found for this network and pool. Skipping mintToTreasury call.\n"));
        } else {
            // Parse reserves from JSON string
            address[] memory assets = abi.decode(poolData, (address[]));
            
            logContent = string(abi.encodePacked(logContent, "Number of assets: ", vm.toString(assets.length), "\n\n"));

            vm.startBroadcast(deployerPrivateKey);

            IPool poolContract = IPool(poolAddress);
            
            // Call mintToTreasury with all assets
            try poolContract.mintToTreasury(assets) {
                logContent = string(abi.encodePacked(logContent, "Successfully minted to treasury\n"));
                for (uint i = 0; i < assets.length; i++) {
                    logContent = string(abi.encodePacked(logContent, "Minted asset: ", vm.toString(assets[i]), "\n"));
                }
            } catch Error(string memory reason) {
                logContent = string(abi.encodePacked(logContent, "Failed to mint to treasury. Reason: ", reason, "\n"));
            } catch (bytes memory lowLevelData) {
                logContent = string(abi.encodePacked(logContent, "Failed to mint to treasury. Low-level error: ", vm.toString(lowLevelData), "\n"));
            }
            
            vm.stopBroadcast();
        }

        // Write log to file
        string memory filename = string(abi.encodePacked("./logs/mint_to_treasury_", network, "_", pool, "_", vm.toString(block.timestamp), ".log"));
        vm.writeFile(filename, logContent);
        
        console.log("Mint to treasury operation completed for", network, pool);
        console.log("Log written to:", filename);
    }
}