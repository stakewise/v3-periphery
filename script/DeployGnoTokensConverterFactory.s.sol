// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {GnoTokensConverter} from '../src/converters/GnoTokensConverter.sol';
import {TokensConverterFactory} from '../src/converters/TokensConverterFactory.sol';
import {SwapOrderHandler} from '../src/converters/SwapOrderHandler.sol';

contract DeployGnoTokensConverterFactory is Script {
    struct ConfigParams {
        address composableCoW;
        address assetToken;
        address relayer;
        address savingsXDaiAdapter;
        address sDaiToken;
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        params.composableCoW = vm.envAddress('COMPOSABLE_COW');
        params.assetToken = vm.envAddress('ASSET_TOKEN');
        params.relayer = vm.envAddress('COWSWAP_RELAYER');
        params.savingsXDaiAdapter = vm.envAddress('SAVINGS_XDAI_ADAPTER');
        params.sDaiToken = vm.envAddress('SDAI_TOKEN');
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy swap order handler.
        SwapOrderHandler swapOrderHandler = new SwapOrderHandler();

        // Deploy tokens converter implementation.
        GnoTokensConverter implementation = new GnoTokensConverter(
            params.composableCoW,
            address(swapOrderHandler),
            params.assetToken,
            params.relayer,
            params.savingsXDaiAdapter,
            params.sDaiToken
        );

        // Deploy tokens converter factory.
        TokensConverterFactory factory = new TokensConverterFactory(address(implementation));
        console.log('TokensConverterFactory deployed at: ', address(factory));

        vm.stopBroadcast();
    }
}
