// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {MockERC20Upgradeable} from "./utils/MockERC20Upgradeable.sol";

import {DSTestPlus} from "lib/solmate/src/test/utils/DSTestPlus.sol";
import {DSInvariantTest} from "lib/solmate/src/test/utils/DSInvariantTest.sol";

import {stdError} from "forge-std/StdError.sol";

contract ERC20UpgradeableTest is DSTestPlus {
	MockERC20Upgradeable token;

	bytes32 constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

	function setUp() public {
		token = new MockERC20Upgradeable();
		token.init("Token", "TKN", 18);
	}

	function invariantMetadata() public {
		assertEq(token.name(), "Token");
		assertEq(token.symbol(), "TKN");
		assertEq(token.decimals(), 18);
	}

	function testMint() public {
		token.mint(address(0xBEEF), 1e18);

		assertEq(token.totalSupply(), 1e18);
		assertEq(token.balanceOf(address(0xBEEF)), 1e18);
	}

	function testBurn() public {
		token.mint(address(0xBEEF), 1e18);
		token.burn(address(0xBEEF), 0.9e18);

		assertEq(token.totalSupply(), 1e18 - 0.9e18);
		assertEq(token.balanceOf(address(0xBEEF)), 0.1e18);
	}

	function testApprove() public {
		assertTrue(token.approve(address(0xBEEF), 1e18));

		assertEq(token.allowance(address(this), address(0xBEEF)), 1e18);
	}

	function testTransfer() public {
		token.mint(address(this), 1e18);

		assertTrue(token.transfer(address(0xBEEF), 1e18));
		assertEq(token.totalSupply(), 1e18);

		assertEq(token.balanceOf(address(this)), 0);
		assertEq(token.balanceOf(address(0xBEEF)), 1e18);
	}

	function testTransferFrom() public {
		address from = address(0xABCD);

		token.mint(from, 1e18);

		hevm.prank(from);
		token.approve(address(this), 1e18);

		assertTrue(token.transferFrom(from, address(0xBEEF), 1e18));
		assertEq(token.totalSupply(), 1e18);

		assertEq(token.allowance(from, address(this)), 0);

		assertEq(token.balanceOf(from), 0);
		assertEq(token.balanceOf(address(0xBEEF)), 1e18);
	}

	function testInfiniteApproveTransferFrom() public {
		address from = address(0xABCD);

		token.mint(from, 1e18);

		hevm.prank(from);
		token.approve(address(this), type(uint256).max);

		assertTrue(token.transferFrom(from, address(0xBEEF), 1e18));
		assertEq(token.totalSupply(), 1e18);

		assertEq(token.allowance(from, address(this)), type(uint256).max);

		assertEq(token.balanceOf(from), 0);
		assertEq(token.balanceOf(address(0xBEEF)), 1e18);
	}

	function testPermit() public {
		uint256 privateKey = 0xBEEF;
		address owner = hevm.addr(privateKey);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			privateKey,
			keccak256(
				abi.encodePacked(
					"\x19\x01",
					token.DOMAIN_SEPARATOR(),
					keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(0xCAFE), 1e18, 0, block.timestamp))
				)
			)
		);

		token.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);

		assertEq(token.allowance(owner, address(0xCAFE)), 1e18);
		assertEq(token.nonces(owner), 1);
	}

	function testRevert_TransferInsufficientBalance() public {
		token.mint(address(this), 0.9e18);
		hevm.expectRevert(stdError.arithmeticError);
		token.transfer(address(0xBEEF), 1e18);
	}

	function testRevert_TransferFromInsufficientAllowance() public {
		address from = address(0xABCD);

		token.mint(from, 1e18);

		hevm.prank(from);
		token.approve(address(this), 0.9e18);

		hevm.expectRevert(stdError.arithmeticError);
		token.transferFrom(from, address(0xBEEF), 1e18);
	}

	function testRevert_TransferFromInsufficientBalance() public {
		address from = address(0xABCD);

		token.mint(from, 0.9e18);

		hevm.prank(from);
		token.approve(address(this), 1e18);

		hevm.expectRevert(stdError.arithmeticError);
		token.transferFrom(from, address(0xBEEF), 1e18);
	}

	function testRevert_PermitBadNonce(uint248 privKey, address to, uint256 amount, uint256 deadline, uint256 nonce) public {
		if (deadline < block.timestamp) deadline = block.timestamp;
		uint256 privateKey = privKey;
		if (privateKey == 0) privateKey = 1;
		if (nonce == 0) nonce = 1;

		address owner = hevm.addr(privateKey);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			privateKey,
			keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), keccak256(abi.encode(PERMIT_TYPEHASH, owner, to, amount, nonce, deadline))))
		);

		hevm.expectRevert(bytes("INVALID_SIGNER"));
		token.permit(owner, to, amount, deadline, v, r, s);
	}

	function testRevert_PermitBadDeadline() public {
		uint256 privateKey = 0xBEEF;
		address owner = hevm.addr(privateKey);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			privateKey,
			keccak256(
				abi.encodePacked(
					"\x19\x01",
					token.DOMAIN_SEPARATOR(),
					keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(0xCAFE), 1e18, 0, block.timestamp))
				)
			)
		);

		hevm.expectRevert(bytes("INVALID_SIGNER"));
		token.permit(owner, address(0xCAFE), 1e18, block.timestamp + 1, v, r, s);
	}

	function testRevert_PermitPastDeadline() public {
		uint256 oldTimestamp = block.timestamp;
		uint256 privateKey = 0xBEEF;
		address owner = hevm.addr(privateKey);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			privateKey,
			keccak256(
				abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(0xCAFE), 1e18, 0, oldTimestamp)))
			)
		);

		hevm.warp(block.timestamp + 1);
		hevm.expectRevert(bytes("PERMIT_DEADLINE_EXPIRED"));
		token.permit(owner, address(0xCAFE), 1e18, oldTimestamp, v, r, s);
	}

	function testRevert_PermitReplay() public {
		uint256 privateKey = 0xBEEF;
		address owner = hevm.addr(privateKey);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			privateKey,
			keccak256(
				abi.encodePacked(
					"\x19\x01",
					token.DOMAIN_SEPARATOR(),
					keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(0xCAFE), 1e18, 0, block.timestamp))
				)
			)
		);

		token.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);
		hevm.expectRevert("INVALID_SIGNER");
		token.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);
	}

	function testMetadata(string calldata name, string calldata symbol, uint8 decimals) public {
		MockERC20Upgradeable tkn = new MockERC20Upgradeable();
		tkn.init(name, symbol, decimals);
		assertEq(tkn.name(), name);
		assertEq(tkn.symbol(), symbol);
		assertEq(tkn.decimals(), decimals);
	}

	function testMint(address from, uint256 amount) public {
		token.mint(from, amount);

		assertEq(token.totalSupply(), amount);
		assertEq(token.balanceOf(from), amount);
	}

	function testBurn(address from, uint256 mintAmount, uint256 burnAmount) public {
		burnAmount = bound(burnAmount, 0, mintAmount);

		token.mint(from, mintAmount);
		token.burn(from, burnAmount);

		assertEq(token.totalSupply(), mintAmount - burnAmount);
		assertEq(token.balanceOf(from), mintAmount - burnAmount);
	}

	function testApprove(address to, uint256 amount) public {
		assertTrue(token.approve(to, amount));

		assertEq(token.allowance(address(this), to), amount);
	}

	function testTransfer(address from, uint256 amount) public {
		token.mint(address(this), amount);

		assertTrue(token.transfer(from, amount));
		assertEq(token.totalSupply(), amount);

		if (address(this) == from) {
			assertEq(token.balanceOf(address(this)), amount);
		} else {
			assertEq(token.balanceOf(address(this)), 0);
			assertEq(token.balanceOf(from), amount);
		}
	}

	function testTransferFrom(address to, uint256 approval, uint256 amount) public {
		amount = bound(amount, 0, approval);

		address from = address(0xABCD);

		token.mint(from, amount);

		hevm.prank(from);
		token.approve(address(this), approval);

		assertTrue(token.transferFrom(from, to, amount));
		assertEq(token.totalSupply(), amount);

		uint256 app = from == address(this) || approval == type(uint256).max ? approval : approval - amount;
		assertEq(token.allowance(from, address(this)), app);

		if (from == to) {
			assertEq(token.balanceOf(from), amount);
		} else {
			assertEq(token.balanceOf(from), 0);
			assertEq(token.balanceOf(to), amount);
		}
	}

	function testPermit(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
		uint256 privateKey = privKey;
		if (deadline < block.timestamp) deadline = block.timestamp;
		if (privateKey == 0) privateKey = 1;

		address owner = hevm.addr(privateKey);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			privateKey,
			keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), keccak256(abi.encode(PERMIT_TYPEHASH, owner, to, amount, 0, deadline))))
		);

		token.permit(owner, to, amount, deadline, v, r, s);

		assertEq(token.allowance(owner, to), amount);
		assertEq(token.nonces(owner), 1);
	}

	function testRevert_BurnInsufficientBalance(address to, uint256 mintAmount, uint256 burnAmount) public {
		hevm.assume(mintAmount < type(uint256).max - 1);
		burnAmount = bound(burnAmount, mintAmount + 1, type(uint256).max);

		token.mint(to, mintAmount);
		hevm.expectRevert(stdError.arithmeticError);
		token.burn(to, burnAmount);
	}

	function testRevert_TransferInsufficientBalance(address to, uint256 mintAmount, uint256 sendAmount) public {
		hevm.assume(mintAmount < type(uint256).max - 1);
		sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);

		token.mint(address(this), mintAmount);
		hevm.expectRevert(stdError.arithmeticError);
		token.transfer(to, sendAmount);
	}

	function testRevert_TransferFromInsufficientAllowance(address to, uint256 approval, uint256 amount) public {
		hevm.assume(approval < type(uint256).max - 1);
		amount = bound(amount, approval + 1, type(uint256).max);

		address from = address(0xABCD);

		token.mint(from, amount);

		hevm.prank(from);
		token.approve(address(this), approval);

		hevm.expectRevert(stdError.arithmeticError);
		token.transferFrom(from, to, amount);
	}

	function testRevert_TransferFromInsufficientBalance(address to, uint256 mintAmount, uint256 sendAmount) public {
		hevm.assume(mintAmount < type(uint256).max - 1);
		sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);

		address from = address(0xABCD);

		token.mint(from, mintAmount);

		hevm.prank(from);
		token.approve(address(this), sendAmount);

		hevm.expectRevert(stdError.arithmeticError);
		token.transferFrom(from, to, sendAmount);
	}

	function testRevert_PermitBadDeadline(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
		deadline = bound(deadline, block.timestamp, type(uint256).max - 1);

		uint256 privateKey = privKey;
		if (privateKey == 0) privateKey = 1;

		address owner = hevm.addr(privateKey);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			privateKey,
			keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), keccak256(abi.encode(PERMIT_TYPEHASH, owner, to, amount, 0, deadline))))
		);

		hevm.expectRevert(bytes("INVALID_SIGNER"));
		token.permit(owner, to, amount, deadline + 1, v, r, s);
	}

	function testRevert_PermitPastDeadline(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
		deadline = bound(deadline, 0, block.timestamp - 1);
		uint256 privateKey = privKey;
		if (privateKey == 0) privateKey = 1;

		address owner = hevm.addr(privateKey);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			privateKey,
			keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), keccak256(abi.encode(PERMIT_TYPEHASH, owner, to, amount, 0, deadline))))
		);

		hevm.expectRevert(bytes("PERMIT_DEADLINE_EXPIRED"));
		token.permit(owner, to, amount, deadline, v, r, s);
	}

	function testRevert_PermitReplay(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
		if (deadline < block.timestamp) deadline = block.timestamp;
		uint256 privateKey = privKey;
		if (privateKey == 0) privateKey = 1;

		address owner = hevm.addr(privateKey);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			privateKey,
			keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), keccak256(abi.encode(PERMIT_TYPEHASH, owner, to, amount, 0, deadline))))
		);

		token.permit(owner, to, amount, deadline, v, r, s);
		hevm.expectRevert("INVALID_SIGNER");
		token.permit(owner, to, amount, deadline, v, r, s);
	}
}

contract ERC20Invariants is DSTestPlus, DSInvariantTest {
	BalanceSum balanceSum;
	MockERC20Upgradeable token;

	function setUp() public {
		token = new MockERC20Upgradeable();
		token.init("Token", "TKN", 18);
		balanceSum = new BalanceSum(token);

		addTargetContract(address(balanceSum));
	}

	function invariantBalanceSum() public {
		assertEq(token.totalSupply(), balanceSum.sum());
	}
}

contract BalanceSum {
	MockERC20Upgradeable token;
	uint256 public sum;

	constructor(MockERC20Upgradeable _token) {
		token = _token;
	}

	function mint(address from, uint256 amount) public {
		token.mint(from, amount);
		sum += amount;
	}

	function burn(address from, uint256 amount) public {
		token.burn(from, amount);
		sum -= amount;
	}

	function approve(address to, uint256 amount) public {
		token.approve(to, amount);
	}

	function transferFrom(address from, address to, uint256 amount) public {
		token.transferFrom(from, to, amount);
	}

	function transfer(address to, uint256 amount) public {
		token.transfer(to, amount);
	}
}
