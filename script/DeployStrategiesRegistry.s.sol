// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {StrategiesRegistry} from '../src/StrategiesRegistry.sol';

contract DeployStrategiesRegistry is Script {
    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Deploy strategies registry.
        StrategiesRegistry strategiesRegistry = new StrategiesRegistry();
        console.log('StrategiesRegistry deployed at: ', address(strategiesRegistry));

        vm.stopBroadcast();
    }

    // excludes this contract from coverage report
    function test() public {}
}
