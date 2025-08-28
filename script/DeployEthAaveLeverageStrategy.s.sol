// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {StrategiesRegistry} from '../src/StrategiesRegistry.sol';
import {EthAaveLeverageStrategy} from '../src/leverage/EthAaveLeverageStrategy.sol';
import {StrategyProxy} from '../src/StrategyProxy.sol';

contract DeployEthAaveLeverageStrategy is Script {
    struct ConfigParams {
        address osToken;
        address assetToken;
        address osTokenVaultController;
        address osTokenConfig;
        address osTokenFlashLoans;
        address osTokenVaultEscrow;
        address balancerVault;
        address aavePool;
        address aaveOsToken;
        address aaveVarDebtAssetToken;
        address rescueVault;
        address governor;
        address strategiesRegistry;
        address strategyProxyImplementation;
        uint256 maxVaultLtvPercent;
        uint256 maxBorrowLtvPercent;
        uint256 vaultForceExitLtvPercent;
        uint256 borrowForceExitLtvPercent;
        uint256 balancerPoolId;
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        params.osToken = vm.envAddress('OS_TOKEN');
        params.assetToken = vm.envAddress('ASSET_TOKEN');
        params.osTokenVaultController = vm.envAddress('OS_TOKEN_VAULT_CONTROLLER');
        params.osTokenConfig = vm.envAddress('OS_TOKEN_CONFIG');
        params.osTokenFlashLoans = vm.envAddress('OS_TOKEN_FLASH_LOANS');
        params.osTokenVaultEscrow = vm.envAddress('OS_TOKEN_VAULT_ESCROW');
        params.balancerVault = vm.envAddress('BALANCER_VAULT');
        params.aavePool = vm.envAddress('AAVE_POOL');
        params.aaveOsToken = vm.envAddress('AAVE_OS_TOKEN');
        params.aaveVarDebtAssetToken = vm.envAddress('AAVE_VAR_DEBT_ASSET_TOKEN');
        params.maxVaultLtvPercent = vm.envUint('MAX_VAULT_LTV_PERCENT');
        params.maxBorrowLtvPercent = vm.envUint('MAX_BORROW_LTV_PERCENT');
        params.vaultForceExitLtvPercent = vm.envUint('VAULT_FORCE_EXIT_LTV_PERCENT');
        params.borrowForceExitLtvPercent = vm.envUint('BORROW_FORCE_EXIT_LTV_PERCENT');
        params.rescueVault = vm.envAddress('RESCUE_VAULT');
        params.balancerPoolId = vm.envUint('BALANCER_POOL_ID');
        params.governor = vm.envAddress('GOVERNOR');
        params.strategiesRegistry = vm.envAddress('STRATEGIES_REGISTRY');
        params.strategyProxyImplementation = vm.envAddress('STRATEGY_PROXY_IMPLEMENTATION');
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy EthAaveLeverageStrategy.
        EthAaveLeverageStrategy strategy = new EthAaveLeverageStrategy(
            params.osToken,
            params.assetToken,
            params.osTokenVaultController,
            params.osTokenConfig,
            params.osTokenFlashLoans,
            params.osTokenVaultEscrow,
            params.strategiesRegistry,
            params.strategyProxyImplementation,
            params.balancerVault,
            params.aavePool,
            params.aaveOsToken,
            params.aaveVarDebtAssetToken
        );
        console.log('EthAaveLeverageStrategy deployed at: ', address(strategy));
        vm.stopBroadcast();
    }
}
