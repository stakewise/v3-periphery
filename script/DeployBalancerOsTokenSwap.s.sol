// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {BalancerOsTokenSwap} from '../src/leverage/BalancerOsTokenSwap.sol';

contract DeployBalancerOsTokenSwap is Script {
    struct ConfigParams {
        address osToken;
        address assetToken;
        address wrappedAssetToken;
        address balancerRouter;
        address balancerPool;
        address permit2;
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        params.osToken = vm.envAddress('OS_TOKEN');
        params.assetToken = vm.envAddress('ASSET_TOKEN');
        params.wrappedAssetToken = vm.envAddress('WRAPPED_ASSET_TOKEN');
        params.balancerRouter = vm.envAddress('BALANCER_ROUTER');
        params.balancerPool = vm.envAddress('BALANCER_POOL');
        params.permit2 = vm.envAddress('PERMIT2');
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy BalancerOsTokenSwap.
        BalancerOsTokenSwap balancerOsTokenSwap = new BalancerOsTokenSwap(
            params.osToken,
            params.assetToken,
            params.wrappedAssetToken,
            params.balancerRouter,
            params.balancerPool,
            params.permit2
        );
        console.log('BalancerOsTokenSwap deployed at: ', address(balancerOsTokenSwap));

        vm.stopBroadcast();
    }
}
