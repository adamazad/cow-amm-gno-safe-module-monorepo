// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {JoinPoolModule} from "../src/JoinPoolModule.sol";

contract DeployCore is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("CONTRACT_DEPLOYER_PRIVATE_KEY");

    vm.startBroadcast(deployerPrivateKey);

    // Deploy the mastercopy (implementation) contract
    JoinPoolModule mastercopy = new JoinPoolModule();

    vm.stopBroadcast();

    // Log the deployed addresses
    console2.log("JoinPoolModule deployed at:", address(mastercopy));

    // Write deployment output as JSON to disk
    string memory jsonOutput =
      string(abi.encodePacked("{\n", '  "joinPoolModule": "', vm.toString(address(mastercopy)), '",\n', "}"));

    uint256 chainId = block.chainid;
    string memory outputPath = string(abi.encodePacked("./deployment_output_", vm.toString(chainId), ".json"));
    vm.writeFile(outputPath, jsonOutput);

    console2.log("Deployment output written to:", outputPath);

    string memory verifyContractsMessage = string(
      abi.encodePacked(
        "\n",
        "Run the following commands to verify the contracts:\n",
        "forge verify-contract ",
        vm.toString(address(mastercopy)),
        " --chain ",
        vm.toString(block.chainid),
        " JoinPoolModule"
      )
    );

    console2.log(verifyContractsMessage);
  }
}
