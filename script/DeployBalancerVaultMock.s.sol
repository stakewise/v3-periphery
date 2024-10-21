// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import {Script} from '../lib/forge-std/src/Script.sol';
import {console} from '../lib/forge-std/src/console.sol';
import {Upgrades, Options} from 'openzeppelin-foundry-upgrades/Upgrades.sol';
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

    // excludes this contract from coverage report
    function test() public {}
}
