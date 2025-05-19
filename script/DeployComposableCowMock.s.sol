// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {ComposableCowMock} from '../src/mocks/ComposableCowMock.sol';

contract DeployComposableCowMock is Script {
    struct ConfigParams {
        address assetToken;
        address governor;
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        params.assetToken = vm.envAddress('ASSET_TOKEN');
        params.governor = vm.envAddress('GOVERNOR');
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy ComposableCow mock.
        address mock = address(new ComposableCowMock(params.governor, params.assetToken));
        console.log('ComposableCowMock deployed at: ', mock);

        vm.stopBroadcast();
    }
}
