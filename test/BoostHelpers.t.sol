// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import 'forge-std/Test.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';
import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {BoostHelpers, IBoostHelpers} from '../src/BoostHelpers.sol';

contract BoostHelpersTest is Test {
    struct TestUser {
        address user;
        address vault;
        IKeeperRewards.HarvestParams harvestParams;
        IBoostHelpers.ExitRequest exitRequest;
        uint256 expectedOsTokenShares;
        uint256 expectedAssets;
        uint256 expectedBorrowLtv;
        uint256 expectedOsTokenLtv;
    }

    uint256 public constant forkBlockNumber = 21_916_340;
    address public constant keeper = 0x6B5815467da09DaA7DC83Db21c9239d98Bb487b5;
    address public constant leverageStrategyV1 = 0x48cD14FDB8e72A03C8D952af081DBB127D6281fc;
    address public constant osTokenCtrl = 0x2A261e60FB14586B474C208b1B7AC6D0f5000306;
    address public constant osTokenEscrow = 0x09e84205DF7c68907e619D07aFD90143c5763605;
    address public constant sharedMevEscrow = 0x48319f97E5Da1233c21c48b80097c0FB7a20Ff86;
    address public constant strategiesRegistry = 0x90b82E4b3aa385B4A02B7EBc1892a4BeD6B5c465;
    address public constant strategyProxyImplementation = 0x2CbE7Ba7f14ac24F3AA6AE2e1A8159670C9C7b75;

    BoostHelpers public boostHelpers;
    TestUser public boostUser;
    TestUser public unboostUser;
    TestUser public notHarvestedVaultUser;
    TestUser public noBoostPositionUser; // User without boost position
    TestUser public withdrawnPositionUser; // User who withdrew their boost position

    function setUp() public {
        vm.createSelectFork(vm.envString('MAINNET_RPC_URL'));
        vm.rollFork(forkBlockNumber);
        boostHelpers = new BoostHelpers(
            keeper,
            leverageStrategyV1,
            strategiesRegistry,
            osTokenCtrl,
            osTokenEscrow,
            sharedMevEscrow,
            strategyProxyImplementation
        );

        bytes32[] memory proof = new bytes32[](6);

        // normal user
        proof[0] = 0x522856d4c8dcaba7abdc296465ca2aaea917ae37ace35595fd72642725ede567;
        proof[1] = 0x19db8aef400f61efdaa0b2b45b3c86c7ce38d72c53a9c237874ac4d31bf26dae;
        proof[2] = 0x4a47a5899f0d77fbe53ee5a882274dd85a52ea6b2d23bbd2175203c229898afe;
        proof[3] = 0x4c8ba14f312579e1dd1b1043ef51fcea65275239bbbd51555751db1d020786e0;
        proof[4] = 0x8cdb8e40170f870b9dcba5bbfa96a6ef4167e7983971825b90cfdd6c50ed2544;
        proof[5] = 0xa08e66785a57107770df7b897ece1f8d2c98bc380b2aef45088cd32ff239dba8;
        boostUser = TestUser({
            user: 0x13cf846853a530b0eD234dDC382DD37eC2460725,
            vault: 0xAC0F906E433d58FA868F936E8A43230473652885,
            harvestParams: IKeeperRewards.HarvestParams({
                rewardsRoot: 0x728664e6559cce31f7f79f0c2d67386adcf29618c76a56a7a936eb20d0b3a6d1,
                reward: 11_167_650_217_113_547_633_930,
                unlockedMevReward: 548_385_949_444_245_074_397,
                proof: proof
            }),
            exitRequest: IBoostHelpers.ExitRequest({positionTicket: 0, timestamp: 0}),
            expectedOsTokenShares: 1_101_224_270_038_765_479,
            expectedAssets: 3_320_079_387_895_743,
            expectedBorrowLtv: 929_821_042_531_042_167,
            expectedOsTokenLtv: 995_079_619_555_973_200
        });

        // user with unboost position
        proof[0] = 0x522856d4c8dcaba7abdc296465ca2aaea917ae37ace35595fd72642725ede567;
        proof[1] = 0x19db8aef400f61efdaa0b2b45b3c86c7ce38d72c53a9c237874ac4d31bf26dae;
        proof[2] = 0x4a47a5899f0d77fbe53ee5a882274dd85a52ea6b2d23bbd2175203c229898afe;
        proof[3] = 0x4c8ba14f312579e1dd1b1043ef51fcea65275239bbbd51555751db1d020786e0;
        proof[4] = 0x8cdb8e40170f870b9dcba5bbfa96a6ef4167e7983971825b90cfdd6c50ed2544;
        proof[5] = 0xa08e66785a57107770df7b897ece1f8d2c98bc380b2aef45088cd32ff239dba8;
        unboostUser = TestUser({
            user: 0x5952f70FEF1CbC26856d149646D4A8F97E923eE7,
            vault: 0xAC0F906E433d58FA868F936E8A43230473652885,
            harvestParams: IKeeperRewards.HarvestParams({
                rewardsRoot: 0x728664e6559cce31f7f79f0c2d67386adcf29618c76a56a7a936eb20d0b3a6d1,
                reward: 11_167_650_217_113_547_633_930,
                unlockedMevReward: 548_385_949_444_245_074_397,
                proof: proof
            }),
            exitRequest: IBoostHelpers.ExitRequest({
                positionTicket: 46_286_395_780_845_057_893_871,
                timestamp: 1_739_934_863
            }),
            expectedOsTokenShares: 109_436_477_264_713,
            expectedAssets: 0,
            expectedBorrowLtv: 929_959_926_131_369_115,
            expectedOsTokenLtv: 995_126_260_333_212_324
        });

        // user from unharvested vault
        proof[0] = 0x5a2617f6bce42a03d7f715e8e836d62d3480cda127803c6236e9a9fa1e7db052;
        proof[1] = 0x66cec6e7c74a139907b29268ff090689dbdcc1fe181de103e978f8b55e513be3;
        proof[2] = 0xef8251a4cf4d3159ed43b5b24371e13d5a2e533567447d6864d0f1f4d206c590;
        proof[3] = 0x2449d9af394be89797ee06d3e94df3a1df61d8d1351a8c1fdd7895cafc285e13;
        proof[4] = 0xf2bc732a0876eef2c878b4d6176c6655381622354eb4b7644274fa97883c8bae;
        proof[5] = 0x5e2c87248f0dc86415ba413b5d7fcffbf3ef518f904545b6194961dff2c63492;
        notHarvestedVaultUser = TestUser({
            user: 0xf506187Dc3f5c4C9C91cFf1D1AD7eaf9e305242F,
            vault: 0x089A97A8bC0C0F016f89F9CF42181Ff06afB2Daf,
            harvestParams: IKeeperRewards.HarvestParams({
                rewardsRoot: 0x728664e6559cce31f7f79f0c2d67386adcf29618c76a56a7a936eb20d0b3a6d1,
                reward: 5_923_134_143_423_208_780,
                unlockedMevReward: 811_766_485_452_869_841,
                proof: proof
            }),
            exitRequest: IBoostHelpers.ExitRequest({
                positionTicket: 46_286_395_780_845_057_893_871,
                timestamp: 1_739_934_863
            }),
            expectedOsTokenShares: 4_725_244_129_138_482_093,
            expectedAssets: 14_308_718_256_134_190,
            expectedBorrowLtv: 929_821_081_306_850_125,
            expectedOsTokenLtv: 899_822_147_456_547_217
        });

        // user without position
        proof[0] = 0x5a2617f6bce42a03d7f715e8e836d62d3480cda127803c6236e9a9fa1e7db052;
        proof[1] = 0x66cec6e7c74a139907b29268ff090689dbdcc1fe181de103e978f8b55e513be3;
        proof[2] = 0xef8251a4cf4d3159ed43b5b24371e13d5a2e533567447d6864d0f1f4d206c590;
        proof[3] = 0x2449d9af394be89797ee06d3e94df3a1df61d8d1351a8c1fdd7895cafc285e13;
        proof[4] = 0xf2bc732a0876eef2c878b4d6176c6655381622354eb4b7644274fa97883c8bae;
        proof[5] = 0x5e2c87248f0dc86415ba413b5d7fcffbf3ef518f904545b6194961dff2c63492;
        noBoostPositionUser = TestUser({
            user: 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045,
            vault: 0xAC0F906E433d58FA868F936E8A43230473652885,
            harvestParams: IKeeperRewards.HarvestParams({
                rewardsRoot: 0x728664e6559cce31f7f79f0c2d67386adcf29618c76a56a7a936eb20d0b3a6d1,
                reward: 11_167_650_217_113_547_633_930,
                unlockedMevReward: 548_385_949_444_245_074_397,
                proof: proof
            }),
            exitRequest: IBoostHelpers.ExitRequest({positionTicket: 0, timestamp: 0}),
            expectedOsTokenShares: 0,
            expectedAssets: 0,
            expectedBorrowLtv: 0,
            expectedOsTokenLtv: 0
        });

        // user with withdrawn position
        proof[0] = 0x3cb48ba599f2a359cd9ddfff23269a8903a95f2b38f3f7ae3e254808d546f344;
        proof[1] = 0x3c06bb8543b9d05bec7f89e5e18fe8c6cb0a75f66b6818f23fb5ddd7b671a114;
        proof[2] = 0x76a8315fa7f44c37292b4d80bca4cee75d151f43c21edf4c9f3719d32541d2fc;
        proof[3] = 0x4c8ba14f312579e1dd1b1043ef51fcea65275239bbbd51555751db1d020786e0;
        proof[4] = 0x8cdb8e40170f870b9dcba5bbfa96a6ef4167e7983971825b90cfdd6c50ed2544;
        proof[5] = 0xa08e66785a57107770df7b897ece1f8d2c98bc380b2aef45088cd32ff239dba8;
        withdrawnPositionUser = TestUser({
            user: 0xD2F060d400f7e32c6594733773ac1277f5b5b3c0,
            vault: 0xe6d8d8aC54461b1C5eD15740EEe322043F696C08,
            harvestParams: IKeeperRewards.HarvestParams({
                rewardsRoot: 0x728664e6559cce31f7f79f0c2d67386adcf29618c76a56a7a936eb20d0b3a6d1,
                reward: 408_368_175_457_000_000_000,
                unlockedMevReward: 0,
                proof: proof
            }),
            exitRequest: IBoostHelpers.ExitRequest({positionTicket: 0, timestamp: 0}),
            expectedOsTokenShares: 15_729_105_186,
            expectedAssets: 0,
            expectedBorrowLtv: 929_995_785_479_068_598,
            expectedOsTokenLtv: 0
        });
    }

    function testBoostUser() public {
        IBoostHelpers.BoostDetails memory details = boostHelpers.getBoostDetails(
            boostUser.user, boostUser.vault, boostUser.harvestParams, boostUser.exitRequest
        );

        assertEq(details.osTokenShares, boostUser.expectedOsTokenShares, 'boostUser osTokenShares mismatch');
        assertEq(details.assets, boostUser.expectedAssets, 'boostUser assets mismatch');
        assertEq(details.borrowLtv, boostUser.expectedBorrowLtv, 'boostUser borrowLtv mismatch');
        assertEq(details.osTokenLtv, boostUser.expectedOsTokenLtv, 'boostUser osTokenLtv mismatch');

        // getBoostOsTokenShares returns: boost.osTokenShares + osTokenCtrl.convertToShares(boost.assets)
        uint256 totalShares = boostHelpers.getBoostOsTokenShares(
            boostUser.user, boostUser.vault, boostUser.harvestParams, boostUser.exitRequest
        );
        uint256 convertedShares = IOsTokenVaultController(osTokenCtrl).convertToShares(boostUser.expectedAssets);
        uint256 expectedTotalShares = boostUser.expectedOsTokenShares + convertedShares;
        assertEq(totalShares, expectedTotalShares, 'boostUser total shares mismatch');
    }

    function testUnboostUser() public {
        IBoostHelpers.BoostDetails memory details = boostHelpers.getBoostDetails(
            unboostUser.user, unboostUser.vault, unboostUser.harvestParams, unboostUser.exitRequest
        );

        assertEq(details.osTokenShares, unboostUser.expectedOsTokenShares, 'unboostUser osTokenShares mismatch');
        assertEq(details.assets, unboostUser.expectedAssets, 'unboostUser assets mismatch');
        assertEq(details.borrowLtv, unboostUser.expectedBorrowLtv, 'unboostUser borrowLtv mismatch');
        assertEq(details.osTokenLtv, unboostUser.expectedOsTokenLtv, 'unboostUser osTokenLtv mismatch');

        uint256 totalShares = boostHelpers.getBoostOsTokenShares(
            unboostUser.user, unboostUser.vault, unboostUser.harvestParams, unboostUser.exitRequest
        );
        uint256 convertedShares = IOsTokenVaultController(osTokenCtrl).convertToShares(unboostUser.expectedAssets);
        uint256 expectedTotalShares = unboostUser.expectedOsTokenShares + convertedShares;
        assertEq(totalShares, expectedTotalShares, 'unboostUser total shares mismatch');

        TestUser memory invalidExitRequest = unboostUser;
        invalidExitRequest.exitRequest.positionTicket = 0;
        vm.expectRevert(Errors.InvalidPosition.selector);
        boostHelpers.getBoostDetails(
            invalidExitRequest.user,
            invalidExitRequest.vault,
            invalidExitRequest.harvestParams,
            invalidExitRequest.exitRequest
        );
    }

    function testNotHarvestedVaultUser() public {
        IBoostHelpers.BoostDetails memory details = boostHelpers.getBoostDetails(
            notHarvestedVaultUser.user,
            notHarvestedVaultUser.vault,
            notHarvestedVaultUser.harvestParams,
            notHarvestedVaultUser.exitRequest
        );

        assertEq(
            details.osTokenShares,
            notHarvestedVaultUser.expectedOsTokenShares,
            'notHarvestedVaultUser osTokenShares mismatch'
        );
        assertEq(details.assets, notHarvestedVaultUser.expectedAssets, 'notHarvestedVaultUser assets mismatch');
        assertEq(details.borrowLtv, notHarvestedVaultUser.expectedBorrowLtv, 'notHarvestedVaultUser borrowLtv mismatch');
        assertEq(
            details.osTokenLtv, notHarvestedVaultUser.expectedOsTokenLtv, 'notHarvestedVaultUser osTokenLtv mismatch'
        );

        uint256 totalShares = boostHelpers.getBoostOsTokenShares(
            notHarvestedVaultUser.user,
            notHarvestedVaultUser.vault,
            notHarvestedVaultUser.harvestParams,
            notHarvestedVaultUser.exitRequest
        );
        uint256 convertedShares =
            IOsTokenVaultController(osTokenCtrl).convertToShares(notHarvestedVaultUser.expectedAssets);
        uint256 expectedTotalShares = notHarvestedVaultUser.expectedOsTokenShares + convertedShares;
        assertEq(totalShares, expectedTotalShares, 'notHarvestedVaultUser total shares mismatch');
    }

    function testNoBoostPositionUser() public {
        IBoostHelpers.BoostDetails memory details = boostHelpers.getBoostDetails(
            noBoostPositionUser.user,
            noBoostPositionUser.vault,
            noBoostPositionUser.harvestParams,
            noBoostPositionUser.exitRequest
        );

        assertEq(
            details.osTokenShares,
            noBoostPositionUser.expectedOsTokenShares,
            'noBoostPositionUser osTokenShares mismatch'
        );
        assertEq(details.assets, noBoostPositionUser.expectedAssets, 'noBoostPositionUser assets mismatch');
        assertEq(details.borrowLtv, noBoostPositionUser.expectedBorrowLtv, 'noBoostPositionUser borrowLtv mismatch');
        assertEq(details.osTokenLtv, noBoostPositionUser.expectedOsTokenLtv, 'noBoostPositionUser osTokenLtv mismatch');
    }

    function testWithdrawnPositionUser() public {
        IBoostHelpers.BoostDetails memory details = boostHelpers.getBoostDetails(
            withdrawnPositionUser.user,
            withdrawnPositionUser.vault,
            withdrawnPositionUser.harvestParams,
            withdrawnPositionUser.exitRequest
        );

        assertEq(
            details.osTokenShares,
            withdrawnPositionUser.expectedOsTokenShares,
            'withdrawnPositionUser osTokenShares mismatch'
        );
        assertEq(details.assets, withdrawnPositionUser.expectedAssets, 'withdrawnPositionUser assets mismatch');
        assertEq(details.borrowLtv, withdrawnPositionUser.expectedBorrowLtv, 'withdrawnPositionUser borrowLtv mismatch');
        assertEq(
            details.osTokenLtv, withdrawnPositionUser.expectedOsTokenLtv, 'withdrawnPositionUser osTokenLtv mismatch'
        );
    }
}
