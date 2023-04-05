// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20Upgradeable} from "../../../contracts/contract/tokens/upgradeable/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MockERC20Upgradeable is Initializable, ERC20Upgradeable {
	function init(
		string memory _name,
		string memory _symbol,
		uint8 _decimals
	) public initializer {
		__ERC20Upgradeable_init(_name, _symbol, _decimals);
	}

	function mint(address to, uint256 value) public virtual {
		_mint(to, value);
	}

	function burn(address from, uint256 value) public virtual {
		_burn(from, value);
	}

	function versionHash() internal pure override returns (bytes32) {
		return keccak256(abi.encodePacked(uint256(2)));
	}
}
