// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IEthVault} from '@stakewise-core/interfaces/IEthVault.sol';
import {EthHelpers} from '@stakewise-test/helpers/EthHelpers.sol';

contract EthTokensConverterTest is EthHelpers {
    ForkContracts public contracts;
    address public user;
    address public vault;

    function setUp() public {
        // Activate Ethereum fork and get contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        address admin = makeAddr('admin');
        user = makeAddr('user');

        // Fund accounts with ETH for testing
        vm.deal(admin, 100 ether);
        vm.deal(user, 100 ether);

        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
            })
        );
        vault = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
    }

    function test_createSwapOrders_invalidToken() public {}

    function test_createSwapOrders_success() public {}
    function test_isValidSignature_success() public {}
    function test_initialize_invalidVault() public {}
    function test_transferAssets_success() public {}
    function test_transferAssets_noBalance() public {}
}
