// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {VaultUserLtvTracker} from '../src/VaultUserLtvTracker.sol';

contract DeployVaultUserLtvTracker is Script {
    struct ConfigParams {
        address keeper;
        address osTokenVaultController;
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        params.keeper = vm.envAddress('KEEPER');
        params.osTokenVaultController = vm.envAddress('OS_TOKEN_VAULT_CONTROLLER');
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy VaultUserLtvTracker.
        VaultUserLtvTracker tracker = new VaultUserLtvTracker(params.keeper, params.osTokenVaultController);
        console.log('VaultUserLtvTracker deployed at: ', address(tracker));

        vm.stopBroadcast();
    }
}
