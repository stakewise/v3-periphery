// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {BoostHelpers} from '../src/BoostHelpers.sol';

contract DeployAaveBoostHelpers is Script {
    struct ConfigParams {
        address keeper;
        address leverageStrategy;
        address osTokenVaultController;
        address osTokenVaultEscrow;
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        params.keeper = vm.envAddress('KEEPER');
        params.leverageStrategy = vm.envAddress('AAVE_LEVERAGE_STRATEGY');
        params.osTokenVaultController = vm.envAddress('OS_TOKEN_VAULT_CONTROLLER');
        params.osTokenVaultEscrow = vm.envAddress('OS_TOKEN_VAULT_ESCROW');
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy BoostHelpers.
        BoostHelpers boostHelpers =
            new BoostHelpers(params.keeper, params.leverageStrategy, params.osTokenVaultController, params.osTokenVaultEscrow);
        console.log('Aave BoostHelpers deployed at: ', address(boostHelpers));

        vm.stopBroadcast();
    }
}
