// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {BoostHelpers} from '../src/BoostHelpers.sol';

contract DeployAaveBoostHelpers is Script {
    struct ConfigParams {
        address keeper;
        address leverageStrategyV1;
        address strategiesRegistry;
        address osTokenVaultController;
        address osTokenVaultEscrow;
        address sharedMevEscrow;
        address strategyProxyImplementation;
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        params.keeper = vm.envAddress('KEEPER');
        params.leverageStrategyV1 = vm.envAddress('AAVE_LEVERAGE_STRATEGY_V1');
        params.strategiesRegistry = vm.envAddress('STRATEGIES_REGISTRY');
        params.osTokenVaultController = vm.envAddress('OS_TOKEN_VAULT_CONTROLLER');
        params.osTokenVaultEscrow = vm.envAddress('OS_TOKEN_VAULT_ESCROW');
        params.sharedMevEscrow = vm.envAddress('SHARED_MEV_ESCROW');
        params.strategyProxyImplementation = vm.envAddress('STRATEGY_PROXY_IMPLEMENTATION');
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy BoostHelpers.
        BoostHelpers boostHelpers = new BoostHelpers(
            params.keeper,
            params.leverageStrategyV1,
            params.strategiesRegistry,
            params.osTokenVaultController,
            params.osTokenVaultEscrow,
            params.sharedMevEscrow,
            params.strategyProxyImplementation
        );
        console.log('Aave BoostHelpers deployed at: ', address(boostHelpers));

        vm.stopBroadcast();
    }
}
