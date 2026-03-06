// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import 'forge-std/Test.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';
import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {BoostHelpers, IBoostHelpers} from '../src/helpers/BoostHelpers.sol';

contract BoostHelpersTest is Test {
    struct TestUser {
        address user;
        address vault;
        IKeeperRewards.HarvestParams harvestParams;
        IBoostHelpers.ExitRequest[] exitRequests;
        uint256 expectedOsTokenShares;
        uint256 expectedAssets;
        uint256 expectedBorrowLtv;
        uint256 expectedOsTokenLtv;
    }

    uint256 public constant forkBlockNumber = 24_590_000;
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
        proof[0] = 0xd1fb015279733ebcdccf0019ed49b08f57a5f1e69ec92b19b9468c383a6296cf;
        proof[1] = 0x313947a6f0211b8a89db0dc504282a246aab99daf624df1103760bd1a23941be;
        proof[2] = 0x941055dd7de858c1d2e11a4aeab96c2c3c9f5408b336fafcb6abacf91bd61a90;
        proof[3] = 0xae4662883b744a2f89cec0a2e7f4069ffb8d8a57f02afd8adf128d59e302a8ae;
        proof[4] = 0x9886f710405857e0abb532957d0c5c52e03690da9b27df8004dca3d94925d475;
        proof[5] = 0x44c7c0c9551bc4487163dfa90079f2aec2d162b7b650df83d2f4a9e7f9f7bf50;
        IBoostHelpers.ExitRequest[] memory emptyExitRequests = new IBoostHelpers.ExitRequest[](0);
        boostUser.user = 0x13cf846853a530b0eD234dDC382DD37eC2460725;
        boostUser.vault = 0xAC0F906E433d58FA868F936E8A43230473652885;
        boostUser.harvestParams = IKeeperRewards.HarvestParams({
            rewardsRoot: 0x55a08dc786e1d094e22ade4bd81a16cb0305208d19120c3497999b9b8593a954,
            reward: 16_053_265_687_382_663_914_870,
            unlockedMevReward: 1_060_411_105_388_361_355_337,
            proof: proof
        });
        boostUser.exitRequests = emptyExitRequests;
        boostUser.expectedOsTokenShares = 1_082_795_615_214_266_982;
        boostUser.expectedAssets = 42_675_136_670_297_202;
        boostUser.expectedBorrowLtv = 930_387_192_220_571_773;
        boostUser.expectedOsTokenLtv = 993_155_856_048_684_479;

        // user with smaller boost position (no longer exiting)
        proof[0] = 0xd1fb015279733ebcdccf0019ed49b08f57a5f1e69ec92b19b9468c383a6296cf;
        proof[1] = 0x313947a6f0211b8a89db0dc504282a246aab99daf624df1103760bd1a23941be;
        proof[2] = 0x941055dd7de858c1d2e11a4aeab96c2c3c9f5408b336fafcb6abacf91bd61a90;
        proof[3] = 0xae4662883b744a2f89cec0a2e7f4069ffb8d8a57f02afd8adf128d59e302a8ae;
        proof[4] = 0x9886f710405857e0abb532957d0c5c52e03690da9b27df8004dca3d94925d475;
        proof[5] = 0x44c7c0c9551bc4487163dfa90079f2aec2d162b7b650df83d2f4a9e7f9f7bf50;
        unboostUser.user = 0x5952f70FEF1CbC26856d149646D4A8F97E923eE7;
        unboostUser.vault = 0xAC0F906E433d58FA868F936E8A43230473652885;
        unboostUser.harvestParams = IKeeperRewards.HarvestParams({
            rewardsRoot: 0x55a08dc786e1d094e22ade4bd81a16cb0305208d19120c3497999b9b8593a954,
            reward: 16_053_265_687_382_663_914_870,
            unlockedMevReward: 1_060_411_105_388_361_355_337,
            proof: proof
        });
        unboostUser.exitRequests = emptyExitRequests;
        unboostUser.expectedOsTokenShares = 43_683_873_197_463;
        unboostUser.expectedAssets = 911_944_764_203;
        unboostUser.expectedBorrowLtv = 930_654_558_911_943_100;
        unboostUser.expectedOsTokenLtv = 993_084_729_329_290_077;

        // user from unharvested vault
        proof[0] = 0xe313d7505307f2c437dc15c4f001f3ed4fc08cd4890d9bbed238c92bbd901559;
        proof[1] = 0x785e970799f16fe4b5ab823b8f863550462904c141d9698512e9f1e79807df80;
        proof[2] = 0x428ba395930c228630c9751b234e6f57ea1566f22f5b793e45ee8b0e5143df1d;
        proof[3] = 0xb308ec7f14cc4dcc1dc83823790f28f3219f82ec7eb5018d48dcf588752be7c1;
        proof[4] = 0xedc27a8537042cdf19ee12dafd46230066b40ca9d0a077ec004639a56e9e50fa;
        proof[5] = 0x44c7c0c9551bc4487163dfa90079f2aec2d162b7b650df83d2f4a9e7f9f7bf50;
        notHarvestedVaultUser.user = 0xf506187Dc3f5c4C9C91cFf1D1AD7eaf9e305242F;
        notHarvestedVaultUser.vault = 0x089A97A8bC0C0F016f89F9CF42181Ff06afB2Daf;
        notHarvestedVaultUser.harvestParams = IKeeperRewards.HarvestParams({
            rewardsRoot: 0x55a08dc786e1d094e22ade4bd81a16cb0305208d19120c3497999b9b8593a954,
            reward: 17_432_962_286_232_694_581,
            unlockedMevReward: 2_072_259_628_203_403_437,
            proof: proof
        });
        notHarvestedVaultUser.exitRequests = emptyExitRequests;
        notHarvestedVaultUser.expectedOsTokenShares = 8_610_372_451_592_374_469;
        notHarvestedVaultUser.expectedAssets = 210_118_634_932_931_157;
        notHarvestedVaultUser.expectedBorrowLtv = 930_619_897_253_501_114;
        notHarvestedVaultUser.expectedOsTokenLtv = 897_238_987_889_839_050;

        // user without position
        proof[0] = 0xd1fb015279733ebcdccf0019ed49b08f57a5f1e69ec92b19b9468c383a6296cf;
        proof[1] = 0x313947a6f0211b8a89db0dc504282a246aab99daf624df1103760bd1a23941be;
        proof[2] = 0x941055dd7de858c1d2e11a4aeab96c2c3c9f5408b336fafcb6abacf91bd61a90;
        proof[3] = 0xae4662883b744a2f89cec0a2e7f4069ffb8d8a57f02afd8adf128d59e302a8ae;
        proof[4] = 0x9886f710405857e0abb532957d0c5c52e03690da9b27df8004dca3d94925d475;
        proof[5] = 0x44c7c0c9551bc4487163dfa90079f2aec2d162b7b650df83d2f4a9e7f9f7bf50;
        noBoostPositionUser.user = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
        noBoostPositionUser.vault = 0xAC0F906E433d58FA868F936E8A43230473652885;
        noBoostPositionUser.harvestParams = IKeeperRewards.HarvestParams({
            rewardsRoot: 0x55a08dc786e1d094e22ade4bd81a16cb0305208d19120c3497999b9b8593a954,
            reward: 16_053_265_687_382_663_914_870,
            unlockedMevReward: 1_060_411_105_388_361_355_337,
            proof: proof
        });
        noBoostPositionUser.exitRequests = emptyExitRequests;
        noBoostPositionUser.expectedOsTokenShares = 0;
        noBoostPositionUser.expectedAssets = 0;
        noBoostPositionUser.expectedBorrowLtv = 0;
        noBoostPositionUser.expectedOsTokenLtv = 0;

        // user with withdrawn position
        proof[0] = 0xe1ce7efda0ff0b8c8ce4da2dd899a03c8bc281d7e01e5b09e3c4a72aabdd7f1d;
        proof[1] = 0x785e970799f16fe4b5ab823b8f863550462904c141d9698512e9f1e79807df80;
        proof[2] = 0x428ba395930c228630c9751b234e6f57ea1566f22f5b793e45ee8b0e5143df1d;
        proof[3] = 0xb308ec7f14cc4dcc1dc83823790f28f3219f82ec7eb5018d48dcf588752be7c1;
        proof[4] = 0xedc27a8537042cdf19ee12dafd46230066b40ca9d0a077ec004639a56e9e50fa;
        proof[5] = 0x44c7c0c9551bc4487163dfa90079f2aec2d162b7b650df83d2f4a9e7f9f7bf50;
        withdrawnPositionUser.user = 0xD2F060d400f7e32c6594733773ac1277f5b5b3c0;
        withdrawnPositionUser.vault = 0xe6d8d8aC54461b1C5eD15740EEe322043F696C08;
        withdrawnPositionUser.harvestParams = IKeeperRewards.HarvestParams({
            rewardsRoot: 0x55a08dc786e1d094e22ade4bd81a16cb0305208d19120c3497999b9b8593a954,
            reward: 2_267_299_792_543_000_000_000,
            unlockedMevReward: 0,
            proof: proof
        });
        withdrawnPositionUser.exitRequests = emptyExitRequests;
        withdrawnPositionUser.expectedOsTokenShares = 0;
        withdrawnPositionUser.expectedAssets = 0;
        withdrawnPositionUser.expectedBorrowLtv = 930_562_041_566_132_194;
        withdrawnPositionUser.expectedOsTokenLtv = 0;
    }

    function testBoostUser() public {
        IBoostHelpers.BoostDetails memory details = boostHelpers.getBoostDetails(
            boostUser.user, boostUser.vault, boostUser.harvestParams, boostUser.exitRequests
        );

        assertEq(details.osTokenShares, boostUser.expectedOsTokenShares, 'boostUser osTokenShares mismatch');
        assertEq(details.assets, boostUser.expectedAssets, 'boostUser assets mismatch');
        assertEq(details.borrowLtv, boostUser.expectedBorrowLtv, 'boostUser borrowLtv mismatch');
        assertEq(details.osTokenLtv, boostUser.expectedOsTokenLtv, 'boostUser osTokenLtv mismatch');

        // getBoostOsTokenShares returns: boost.osTokenShares + osTokenCtrl.convertToShares(boost.assets)
        uint256 totalShares = boostHelpers.getBoostOsTokenShares(
            boostUser.user, boostUser.vault, boostUser.harvestParams, boostUser.exitRequests
        );
        uint256 convertedShares = IOsTokenVaultController(osTokenCtrl).convertToShares(boostUser.expectedAssets);
        uint256 expectedTotalShares = boostUser.expectedOsTokenShares + convertedShares;
        assertEq(totalShares, expectedTotalShares, 'boostUser total shares mismatch');
    }

    function testUnboostUser() public {
        IBoostHelpers.BoostDetails memory details = boostHelpers.getBoostDetails(
            unboostUser.user, unboostUser.vault, unboostUser.harvestParams, unboostUser.exitRequests
        );

        assertEq(details.osTokenShares, unboostUser.expectedOsTokenShares, 'unboostUser osTokenShares mismatch');
        assertEq(details.assets, unboostUser.expectedAssets, 'unboostUser assets mismatch');
        assertEq(details.borrowLtv, unboostUser.expectedBorrowLtv, 'unboostUser borrowLtv mismatch');
        assertEq(details.osTokenLtv, unboostUser.expectedOsTokenLtv, 'unboostUser osTokenLtv mismatch');

        uint256 totalShares = boostHelpers.getBoostOsTokenShares(
            unboostUser.user, unboostUser.vault, unboostUser.harvestParams, unboostUser.exitRequests
        );
        uint256 convertedShares = IOsTokenVaultController(osTokenCtrl).convertToShares(unboostUser.expectedAssets);
        uint256 expectedTotalShares = unboostUser.expectedOsTokenShares + convertedShares;
        assertEq(totalShares, expectedTotalShares, 'unboostUser total shares mismatch');

        IBoostHelpers.ExitRequest[] memory invalidExitRequests = new IBoostHelpers.ExitRequest[](1);
        invalidExitRequests[0] = IBoostHelpers.ExitRequest({positionTicket: 0, timestamp: 1_739_934_863});
        vm.expectRevert(Errors.InvalidPosition.selector);
        boostHelpers.getBoostDetails(
            unboostUser.user, unboostUser.vault, unboostUser.harvestParams, invalidExitRequests
        );
    }

    function testNotHarvestedVaultUser() public {
        IBoostHelpers.BoostDetails memory details = boostHelpers.getBoostDetails(
            notHarvestedVaultUser.user,
            notHarvestedVaultUser.vault,
            notHarvestedVaultUser.harvestParams,
            notHarvestedVaultUser.exitRequests
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
            notHarvestedVaultUser.exitRequests
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
            noBoostPositionUser.exitRequests
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
            withdrawnPositionUser.exitRequests
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
