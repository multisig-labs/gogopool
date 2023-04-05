// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";
import {ProtocolDAO} from "../../contracts/contract/ProtocolDAO.sol";

contract ProtocolDAOTest is BaseTest {
	function setUp() public override {
		super.setUp();
	}

	function testGetInflation() public view {
		assert(dao.getInflationIntervalRate() > 0);
		assert(dao.getInflationIntervalSeconds() != 0);
	}

	function testPauseContract() public {
		vm.startPrank(address(123));
		vm.expectRevert(BaseAbstract.InvalidOrOutdatedContract.selector);
		dao.pauseContract("TokenggAVAX");
		vm.expectRevert(BaseAbstract.InvalidOrOutdatedContract.selector);
		dao.pauseContract("MinipoolManager");
		assertFalse(dao.getContractPaused("TokenggAVAX"));
		assertFalse(dao.getContractPaused("MinipoolManager"));
		vm.stopPrank();

		vm.startPrank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");
		dao.pauseContract("MinipoolManager");
		assertTrue(dao.getContractPaused("TokenggAVAX"));
		assertTrue(dao.getContractPaused("MinipoolManager"));
		vm.stopPrank();
	}

	function testResumeContract() public {
		vm.startPrank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");
		assertTrue(dao.getContractPaused("TokenggAVAX"));
		dao.resumeContract("TokenggAVAX");
		assertFalse(dao.getContractPaused("TokenggAVAX"));
		vm.stopPrank();
	}

	function testGetRewardsEligibilityMinSeconds() public {
		assertEq(dao.getRewardsEligibilityMinSeconds(), 14 days);
	}

	function testGetRewardsCycleSeconds() public {
		assertEq(dao.getRewardsCycleSeconds(), 28 days);
	}

	function testGetClaimingContractPct() public {
		assertEq(dao.getClaimingContractPct("MultisigManager"), 0.20 ether);
		assertEq(dao.getClaimingContractPct("ClaimNodeOp"), 0.70 ether);
		assertEq(dao.getClaimingContractPct("ClaimProtocolDAO"), 0.10 ether);
	}

	function testSetClaimingContractPct() public {
		assertEq(dao.getClaimingContractPct("MultisigManager"), 0.20 ether);
		assertEq(dao.getClaimingContractPct("ClaimNodeOp"), 0.70 ether);
		assertEq(dao.getClaimingContractPct("ClaimProtocolDAO"), 0.10 ether);

		vm.startPrank(address(ocyticus));
		vm.expectRevert(BaseAbstract.MustBeGuardian.selector);
		dao.setClaimingContractPct("MultisigManager", 0.70 ether);
		vm.stopPrank();

		vm.startPrank(address(guardian));
		dao.setClaimingContractPct("MultisigManager", 0.70 ether);
		assertEq(dao.getClaimingContractPct("MultisigManager"), 0.70 ether);
		dao.setClaimingContractPct("ClaimNodeOp", 0.10 ether);
		assertEq(dao.getClaimingContractPct("ClaimNodeOp"), 0.10 ether);
		dao.setClaimingContractPct("ClaimProtocolDAO", 0.20 ether);
		assertEq(dao.getClaimingContractPct("ClaimProtocolDAO"), 0.20 ether);
		vm.stopPrank();
	}

	function testSetClaimingContractPctGreaterThanOne() public {
		assertEq(dao.getClaimingContractPct("ClaimNodeOp"), 0.70 ether);

		vm.startPrank(address(guardian));
		vm.expectRevert(ProtocolDAO.ValueNotWithinRange.selector);
		dao.setClaimingContractPct("ClaimNodeOp", 1.70 ether);
		vm.stopPrank();

		assertEq(dao.getClaimingContractPct("ClaimNodeOp"), 0.70 ether);
	}

	function testGetInflationIntervalRate() public {
		assertEq(dao.getInflationIntervalRate(), 1000133680617113500);
		assertGt(dao.getInflationIntervalRate(), 1 ether);
	}

	function testGetInflationIntervalSeconds() public {
		assertEq(dao.getInflationIntervalSeconds(), 1 days);
	}

	function testGetMinipoolMinAVAXStakingAmt() public {
		assertEq(dao.getMinipoolMinAVAXStakingAmt(), 2000 ether);
	}

	function testGetMinipoolNodeCommissionFeePct() public {
		assertEq(dao.getMinipoolNodeCommissionFeePct(), 0.15 ether);
	}

	function testGetMinipoolMaxAVAXAssignment() public {
		assertEq(dao.getMinipoolMaxAVAXAssignment(), 10000 ether);
	}

	function testGetMinipoolMinAVAXAssignment() public {
		assertEq(dao.getMinipoolMinAVAXAssignment(), 1000 ether);
	}

	function testGetExpectedAVAXRewardsRate() public {
		assertEq(dao.getExpectedAVAXRewardsRate(), 0.1 ether);
	}

	function testSetExpectedAVAXRewardsRate() public {
		assertEq(dao.getExpectedAVAXRewardsRate(), 0.1 ether);

		vm.startPrank(address(ocyticus));
		vm.expectRevert(BaseAbstract.MustBeMultisig.selector);
		dao.setExpectedAVAXRewardsRate(0.2 ether);
		vm.stopPrank();

		vm.startPrank(address(rialto));
		dao.setExpectedAVAXRewardsRate(0.2 ether);
		assertEq(dao.getExpectedAVAXRewardsRate(), 0.2 ether);
		vm.stopPrank();
	}

	function testSetExpectedAVAXRewardsRateGreaterThanOne() public {
		assertEq(dao.getExpectedAVAXRewardsRate(), 0.1 ether);

		vm.startPrank(address(rialto));
		vm.expectRevert(ProtocolDAO.ValueNotWithinRange.selector);
		dao.setExpectedAVAXRewardsRate(1.1 ether);
		vm.stopPrank();

		assertEq(dao.getExpectedAVAXRewardsRate(), 0.1 ether);
	}

	function testGetMaxCollateralizationRatio() public {
		assertEq(dao.getMaxCollateralizationRatio(), 1.50 ether);
	}

	function testGetMinCollateralizationRatio() public {
		assertEq(dao.getMinCollateralizationRatio(), 0.1 ether);
	}

	function testGetTargetGGAVAXReserveRate() public {
		assertEq(dao.getTargetGGAVAXReserveRate(), 0.1 ether);
	}

	function testGetMinipoolCancelMoratoriumSeconds() public {
		assertEq(dao.getMinipoolCancelMoratoriumSeconds(), 5);
	}

	function testRegisterContract() public {
		address addr = randAddress();
		string memory name = "TestContract";
		bytes32 testKey = "testKey";

		vm.startPrank(addr);
		vm.expectRevert(BaseAbstract.InvalidOrOutdatedContract.selector);
		store.setBool(testKey, true);
		vm.stopPrank();

		vm.prank(guardian);
		dao.registerContract(name, addr);

		assertEq(store.getBool(keccak256(abi.encodePacked("contract.exists", addr))), true);
		assertEq(store.getAddress(keccak256(abi.encodePacked("contract.address", name))), addr);
		assertEq(store.getString(keccak256(abi.encodePacked("contract.name", addr))), name);

		vm.prank(addr);
		store.setBool(testKey, true);
		assertEq(store.getBool(testKey), true);
	}

	function testRegisterContractNotGuardian() public {
		address addr = randAddress();
		string memory name = "newContract";

		vm.startPrank(address(123));
		vm.expectRevert(BaseAbstract.MustBeGuardian.selector);
		dao.registerContract(name, addr);
		vm.stopPrank();
	}

	function testRegisterContractAlreadyRegistered() public {
		address addr = randAddress();
		string memory name = "newContract";

		vm.prank(guardian);
		dao.registerContract(name, addr);

		address newAddr = randAddress();
		vm.startPrank(guardian);
		vm.expectRevert(ProtocolDAO.ContractAlreadyRegistered.selector);
		dao.registerContract(name, newAddr);
		vm.stopPrank();
	}

	function testRegisterContractInvalid() public {
		address addr = randAddress();
		string memory name = "newContract";

		vm.startPrank(guardian);
		vm.expectRevert(ProtocolDAO.InvalidContract.selector);
		dao.registerContract("", addr);

		vm.expectRevert(ProtocolDAO.InvalidContract.selector);
		dao.registerContract(name, address(0));
		vm.stopPrank();
	}

	function testUnregisterContract() public {
		address addr = randAddress();
		string memory name = "TestContract";

		vm.prank(guardian);
		dao.registerContract(name, addr);

		assertEq(store.getBool(keccak256(abi.encodePacked("contract.exists", addr))), true);
		assertEq(store.getAddress(keccak256(abi.encodePacked("contract.address", name))), addr);
		assertEq(store.getString(keccak256(abi.encodePacked("contract.name", addr))), name);

		bytes32 testKey = "testKey";
		vm.prank(addr);
		store.setBool(testKey, true);
		assertEq(store.getBool(testKey), true);

		vm.prank(guardian);
		dao.unregisterContract(name);

		assertEq(store.getBool(keccak256(abi.encodePacked("contract.exists", addr))), false);
		assertEq(store.getAddress(keccak256(abi.encodePacked("contract.address", name))), address(0));
		assertEq(store.getString(keccak256(abi.encodePacked("contract.name", addr))), "");

		vm.startPrank(addr);
		vm.expectRevert(BaseAbstract.InvalidOrOutdatedContract.selector);
		store.setBool(testKey, true);
		vm.stopPrank();
	}

	function testUnregisterContractNotGuardian() public {
		string memory name = "TestContract";

		vm.startPrank(address(123));
		vm.expectRevert(BaseAbstract.MustBeGuardian.selector);
		dao.unregisterContract(name);
	}

	function testUpgradeContract() public {
		address addr = randAddress();
		string memory name = "TestContract";

		address newAddr = randAddress();

		vm.prank(guardian);
		dao.registerContract(name, addr);
		assertEq(store.getBool(keccak256(abi.encodePacked("contract.exists", addr))), true);
		assertEq(store.getAddress(keccak256(abi.encodePacked("contract.address", name))), addr);
		assertEq(store.getString(keccak256(abi.encodePacked("contract.name", addr))), name);

		vm.prank(guardian);
		dao.upgradeContract(name, addr, newAddr);
		// verify new address is set
		assertTrue(store.getBool(keccak256(abi.encodePacked("contract.exists", newAddr))));
		assertEq(store.getAddress(keccak256(abi.encodePacked("contract.address", name))), newAddr);
		assertEq(store.getString(keccak256(abi.encodePacked("contract.name", newAddr))), name);

		// verify old address is deleted
		assertFalse(store.getBool(keccak256(abi.encodePacked("contract.exists", addr))));
		assertEq(store.getString(keccak256(abi.encodePacked("contract.name", addr))), "");

		bytes32 testKey = "testKey";

		vm.startPrank(addr);
		vm.expectRevert(BaseAbstract.InvalidOrOutdatedContract.selector);
		store.setBool(testKey, true);
		vm.stopPrank();

		vm.prank(newAddr);
		store.setBool(testKey, true);
		assertEq(store.getBool(testKey), true);
	}

	function testUpgradeContractNotGuardian() public {
		address addr = randAddress();
		string memory name = "newContract";

		address existingAddr = randAddress();

		vm.startPrank(address(123));
		vm.expectRevert(BaseAbstract.MustBeGuardian.selector);
		dao.upgradeContract(name, addr, existingAddr);
		vm.stopPrank();
	}

	function testUpgradeContractExistingNotRegistered() public {
		// setup existing contract
		address addr = randAddress();
		string memory name = "TestContract";

		vm.prank(guardian);
		dao.registerContract(name, addr);

		address newAddr = randAddress();

		// attempt upgrade with bad name
		vm.startPrank(guardian);
		vm.expectRevert(ProtocolDAO.ExistingContractNotRegistered.selector);
		dao.upgradeContract("BadName", addr, newAddr);

		// attempt upgrade with bad address
		vm.expectRevert(ProtocolDAO.ExistingContractNotRegistered.selector);
		dao.upgradeContract(name, randAddress(), newAddr);
		vm.stopPrank();
	}

	function testUpgradeContractInvalid() public {
		// setup existing contract
		address addr = randAddress();
		string memory name = "TestContract";

		vm.prank(guardian);
		dao.registerContract(name, addr);

		// attempt upgrade with invalid new address
		vm.startPrank(guardian);
		vm.expectRevert(ProtocolDAO.InvalidContract.selector);
		dao.upgradeContract(name, addr, address(0));
	}

	function testUpgradeProtocolDAO() public {
		// set something with the existing dao
		vm.prank(guardian);
		dao.setClaimingContractPct("TestContract", 0.2 ether);

		ProtocolDAO newDao = new ProtocolDAO(store);

		// upgrade dao
		vm.prank(guardian);
		dao.upgradeContract("ProtocolDAO", address(dao), address(newDao));

		// verify new addresses
		assertTrue(store.getBool(keccak256(abi.encodePacked("contract.exists", address(newDao)))));
		assertEq(store.getAddress(keccak256(abi.encodePacked("contract.address", "ProtocolDAO"))), address(newDao));
		assertEq(store.getString(keccak256(abi.encodePacked("contract.name", address(newDao)))), "ProtocolDAO");

		// verify new dao works
		assertEq(dao.getClaimingContractPct("TestContract"), 0.2 ether);

		assertFalse(store.getBool(keccak256(abi.encodePacked("contract.exists", address(dao)))));
		assertEq(store.getString(keccak256(abi.encodePacked("contract.name", address(dao)))), "");
	}
}
