// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {Upgrades, Options} from '@openzeppelin/foundry-upgrades/Upgrades.sol';
import {BalancerVaultMock} from '../src/mocks/BalancerVaultMock.sol';

contract DeployBalancerVaultMock is Script {
    struct ConfigParams {
        address osToken;
        address assetToken;
        address osTokenVaultController;
        address governor;
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        params.osToken = vm.envAddress('OS_TOKEN');
        params.assetToken = vm.envAddress('ASSET_TOKEN');
        params.osTokenVaultController = vm.envAddress('OS_TOKEN_VAULT_CONTROLLER');
        params.governor = vm.envAddress('GOVERNOR');
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy BalancerVaultMock mock.
        Options memory balancerVaultMockOpts;
        balancerVaultMockOpts.constructorData =
            abi.encode(params.osToken, params.assetToken, params.osTokenVaultController);
        address balancerVaultMock = Upgrades.deployUUPSProxy(
            'BalancerVaultMock.sol',
            abi.encodeCall(BalancerVaultMock.initialize, (params.governor)),
            balancerVaultMockOpts
        );
        console.log('BalancerVaultMock deployed at: ', balancerVaultMock);

        vm.stopBroadcast();
    }
}
