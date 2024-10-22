// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import {Script} from '../lib/forge-std/src/Script.sol';
import {console} from '../lib/forge-std/src/console.sol';
import {Upgrades, Options} from 'openzeppelin-foundry-upgrades/Upgrades.sol';
import {AaveMock} from '../src/mocks/AaveMock.sol';
import {AaveOsTokenMock} from '../src/mocks/AaveOsTokenMock.sol';
import {AaveVarDebtAssetTokenMock} from '../src/mocks/AaveVarDebtAssetTokenMock.sol';

contract DeployAaveMock is Script {
    struct ConfigParams {
        address osToken;
        address assetToken;
        address osTokenVaultController;
        address governor;
        uint256 varInterestRatePerSecond;
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        params.osToken = vm.envAddress('OS_TOKEN');
        params.assetToken = vm.envAddress('ASSET_TOKEN');
        params.osTokenVaultController = vm.envAddress('OS_TOKEN_VAULT_CONTROLLER');
        params.varInterestRatePerSecond = vm.envUint('AAVE_MOCK_VAR_INTEREST_RATE_PER_SECOND');
        params.governor = vm.envAddress('GOVERNOR');
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy Aave mock.
        Options memory aaveMockOpts;
        aaveMockOpts.constructorData = abi.encode(params.osToken, params.assetToken, params.osTokenVaultController);
        address aaveMock = Upgrades.deployUUPSProxy(
            'AaveMock.sol',
            abi.encodeCall(AaveMock.initialize, (params.governor, params.varInterestRatePerSecond)),
            aaveMockOpts
        );
        console.log('AaveMock deployed at: ', aaveMock);

        // Deploy Aave OsToken mock.
        Options memory aaveOsTokenMockOpts;
        aaveOsTokenMockOpts.constructorData = abi.encode(aaveMock);
        address aaveOsTokenMock = Upgrades.deployUUPSProxy(
            'AaveOsTokenMock.sol', abi.encodeCall(AaveOsTokenMock.initialize, (params.governor)), aaveOsTokenMockOpts
        );
        console.log('AaveOsTokenMock deployed at: ', aaveOsTokenMock);

        // Deploy Aave VarDebtAssetToken mock.
        Options memory aaveVarDebtAssetTokenMockOpts;
        aaveVarDebtAssetTokenMockOpts.constructorData = abi.encode(aaveMock);
        address aaveVarDebtAssetTokenMock = Upgrades.deployUUPSProxy(
            'AaveVarDebtAssetTokenMock.sol',
            abi.encodeCall(AaveVarDebtAssetTokenMock.initialize, (params.governor)),
            aaveVarDebtAssetTokenMockOpts
        );
        console.log('AaveVarDebtAssetTokenMock deployed at: ', address(aaveVarDebtAssetTokenMock));

        vm.stopBroadcast();
    }
}
