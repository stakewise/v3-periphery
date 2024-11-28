// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {StakeHelpers} from '../src/StakeHelpers.sol';

contract DeployStakeHelpers is Script {
    struct ConfigParams {
        address keeper;
        address osTokenConfigV1;
        address osTokenConfig;
        address osTokenVaultController;
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        params.keeper = vm.envAddress('KEEPER');
        params.osTokenConfigV1 = vm.envAddress('OS_TOKEN_CONFIG_V1');
        params.osTokenConfig = vm.envAddress('OS_TOKEN_CONFIG');
        params.osTokenVaultController = vm.envAddress('OS_TOKEN_VAULT_CONTROLLER');
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy StakeHelpers.
        StakeHelpers stakeHelpers =
            new StakeHelpers(params.keeper, params.osTokenConfigV1, params.osTokenConfig, params.osTokenVaultController);
        console.log('StakeHelpers deployed at: ', address(stakeHelpers));

        vm.stopBroadcast();
    }
}
