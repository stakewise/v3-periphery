// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
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
        address implementation = address(new AaveMock(params.osToken, params.assetToken, params.osTokenVaultController));
        address aaveMock = address(new ERC1967Proxy(implementation, ''));
        AaveMock(aaveMock).initialize(params.governor, params.varInterestRatePerSecond);
        console.log('AaveMock deployed at: ', aaveMock);

        // Deploy Aave OsToken mock.
        implementation = address(new AaveOsTokenMock(aaveMock));
        address aaveOsTokenMock = address(new ERC1967Proxy(implementation, ''));
        AaveOsTokenMock(aaveOsTokenMock).initialize(params.governor);
        console.log('AaveOsTokenMock deployed at: ', aaveOsTokenMock);

        // Deploy Aave VarDebtAssetToken mock.
        implementation = address(new AaveVarDebtAssetTokenMock(aaveMock));
        address aaveVarDebtAssetTokenMock = address(new ERC1967Proxy(implementation, ''));
        AaveVarDebtAssetTokenMock(aaveVarDebtAssetTokenMock).initialize(params.governor);
        console.log('AaveVarDebtAssetTokenMock deployed at: ', address(aaveVarDebtAssetTokenMock));

        vm.stopBroadcast();
    }
}
