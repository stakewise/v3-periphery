// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {OsTokenVaultEscrowAuth} from '../src/OsTokenVaultEscrowAuth.sol';

contract DeployOsTokenVaultEscrowAuth is Script {
    struct ConfigParams {
        address strategiesRegistry;
        address vaultsRegistry;
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        params.strategiesRegistry = vm.envAddress('STRATEGIES_REGISTRY');
        params.vaultsRegistry = vm.envAddress('VAULTS_REGISTRY');
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy OsTokenVaultEscrowAuth
        OsTokenVaultEscrowAuth osTokenVaultEscrowAuth =
            new OsTokenVaultEscrowAuth(params.vaultsRegistry, params.strategiesRegistry);
        console.log('OsTokenVaultEscrowAuth deployed at: ', address(osTokenVaultEscrowAuth));

        vm.stopBroadcast();
    }
}
