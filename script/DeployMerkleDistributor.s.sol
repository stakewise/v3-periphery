// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {MerkleDistributor} from '../src/MerkleDistributor.sol';

contract DeployMerkleDistributor is Script {
    struct ConfigParams {
        address keeper;
        address governor;
        uint64 rewardsDelay;
        uint64 rewardsMinOracles;
    }

    function _readEnvVariables() internal view returns (ConfigParams memory params) {
        params.keeper = vm.envAddress('KEEPER');
        params.rewardsDelay = SafeCast.toUint64(vm.envUint('MERKLE_DISTRIBUTOR_REWARDS_DELAY'));
        params.rewardsMinOracles = SafeCast.toUint64(vm.envUint('MERKLE_DISTRIBUTOR_REWARDS_MIN_ORACLES'));
        params.governor = vm.envAddress('GOVERNOR');
    }

    function run() external {
        vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

        console.log('Deploying from: ', msg.sender);

        // Read environment variables.
        ConfigParams memory params = _readEnvVariables();

        // Deploy MerkleDistributor
        MerkleDistributor merkleDistributor = new MerkleDistributor(
            params.keeper,
            params.governor,
            params.rewardsDelay,
            params.rewardsMinOracles
        );
        console.log('MerkleDistributor deployed at: ', address(merkleDistributor));

        vm.stopBroadcast();
    }
}
