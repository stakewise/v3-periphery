// SPDX-License-Identifier: MIT

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
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy strategies registry.
        StrategiesRegistry strategiesRegistry = new StrategiesRegistry();
        console.log('StrategiesRegistry deployed at: ', address(strategiesRegistry));

        // Deploy strategy proxy implementation.
        StrategyProxy strategyProxyImpl = new StrategyProxy();
        console.log('StrategyProxy implementation deployed at: ', address(strategyProxyImpl));

        // Deploy EthAaveLeverageStrategy.
        EthAaveLeverageStrategy strategy = new EthAaveLeverageStrategy(
            params.osToken,
            params.assetToken,
            params.osTokenVaultController,
            params.osTokenConfig,
            params.osTokenFlashLoans,
            params.osTokenVaultEscrow,
            address(strategiesRegistry),
            address(strategyProxyImpl),
            params.balancerVault,
            params.aavePool,
            params.aaveOsToken,
            params.aaveVarDebtAssetToken
        );
        console.log('EthAaveLeverageStrategy deployed at: ', address(strategy));

        strategiesRegistry.setStrategy(address(strategy), true);
        strategiesRegistry.setStrategyConfig(
            strategy.strategyId(), 'maxVaultLtvPercent', abi.encode(params.maxVaultLtvPercent)
        );
        strategiesRegistry.setStrategyConfig(
            strategy.strategyId(), 'maxBorrowLtvPercent', abi.encode(params.maxBorrowLtvPercent)
        );
        strategiesRegistry.setStrategyConfig(
            strategy.strategyId(), 'vaultForceExitLtvPercent', abi.encode(params.vaultForceExitLtvPercent)
        );
        strategiesRegistry.setStrategyConfig(
            strategy.strategyId(), 'borrowForceExitLtvPercent', abi.encode(params.borrowForceExitLtvPercent)
        );
        strategiesRegistry.setStrategyConfig(strategy.strategyId(), 'rescueVault', abi.encode(params.rescueVault));
        strategiesRegistry.setStrategyConfig(strategy.strategyId(), 'balancerPoolId', abi.encode(params.balancerPoolId));
        strategiesRegistry.initialize(params.governor);

        vm.stopBroadcast();
    }

    // excludes this contract from coverage report
    function test() public {}
}
