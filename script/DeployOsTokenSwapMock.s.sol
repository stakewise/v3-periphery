// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {OsTokenSwapMock} from '../src/mocks/OsTokenSwapMock.sol';

contract DeployOsTokenSwapMock is Script {
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

        // Deploy OsTokenSwapMock.
        address implementation =
            address(new OsTokenSwapMock(params.osToken, params.assetToken, params.osTokenVaultController));
        address osTokenSwapMock = address(new ERC1967Proxy(implementation, ''));
        OsTokenSwapMock(osTokenSwapMock).initialize(params.governor);
        console.log('OsTokenSwapMock deployed at: ', osTokenSwapMock);

        vm.stopBroadcast();
    }
}
