// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IUniswapV2Pair} from "../interface/IUniswapV2Pair.sol";
import {IERC20} from "../interface/IERC20.sol";

// Stripped down https://github.com/Uniswap/solidity-lib/blob/master/contracts/libraries/FixedPoint.sol#LL10C7-L10C7
library FixedPoint {
	// range: [0, 2**112 - 1]
	// resolution: 1 / 2**112
	struct uq112x112 {
		uint224 _x;
	}

	// range: [0, 2**144 - 1]
	// resolution: 1 / 2**112
	struct uq144x112 {
		uint256 _x;
	}

	uint8 public constant RESOLUTION = 112;
	uint256 public constant Q112 = 0x10000000000000000000000000000; // 2**112

	// decode a UQ144x112 into a uint144 by truncating after the radix point
	function decode144(uq144x112 memory self) internal pure returns (uint144) {
		return uint144(self._x >> RESOLUTION);
	}

	// multiply a UQ112x112 by a uint, returning a UQ144x112
	// reverts on overflow
	function mul(uq112x112 memory self, uint256 y) internal pure returns (uq144x112 memory) {
		uint256 z = 0;
		require(y == 0 || (z = uint256(self._x) * y) / y == uint256(self._x), "FixedPoint::OVERFLOW");
		return uq144x112(z);
	}

	// returns a UQ112x112 which represents the ratio of the numerator to the denominator
	function fraction(uint256 numerator, uint256 denominator) internal pure returns (uq112x112 memory) {
		require(denominator > 0, "FixedPoint::DIV_BY_ZERO");
		require(numerator <= type(uint144).max, "FixedPoint::OUT_OF_RANGE");
		if (numerator == 0) return FixedPoint.uq112x112(0);

		uint256 result = (numerator << RESOLUTION) / denominator;
		require(result <= type(uint224).max, "FixedPoint::OVERFLOW");
		return uq112x112(uint224(result));
	}
}

contract TwapGGP {
	using FixedPoint for *;

	error InsufficientElapsedTime();

	event GGPPriceUpdated(uint256 indexed price, uint256 timestamp);

	address public pair;
	uint32 public timePeriod;

	uint32 public blockTimestampLast;
	uint256 public price0CumulativeLast;
	uint144 public price0Average;

	constructor(address _pair, uint32 _timePeriod) {
		pair = _pair;
		timePeriod = _timePeriod;
		(uint256 price0Cumulative, , uint32 blockTimestamp) = currentCumulativePrices();
		price0CumulativeLast = price0Cumulative;
		blockTimestampLast = blockTimestamp;
		price0Average = ggpSpotPriceInAVAX();
	}

	function update() external {
		(uint256 price0Cumulative, , uint32 blockTimestamp) = currentCumulativePrices();
		unchecked {
			uint32 timeElapsed = blockTimestamp - blockTimestampLast;

			if (timeElapsed < timePeriod) {
				revert InsufficientElapsedTime();
			}

			// overflow is desired, casting never truncates
			// cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
			price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)).mul(1e18).decode144();
			price0CumulativeLast = price0Cumulative;
			blockTimestampLast = blockTimestamp;
		}

		emit GGPPriceUpdated(price0Average, blockTimestamp);
	}

	// Twap price averaged over last update() until now
	function ggpTwapPriceInAVAX() public view returns (uint144) {
		(uint256 price0Cumulative, , uint32 blockTimestamp) = currentCumulativePrices();
		unchecked {
			uint32 timeElapsed = blockTimestamp - blockTimestampLast;
			if (timeElapsed == 0) {
				return price0Average;
			} else {
				uint144 priceAvg = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)).mul(1e18).decode144();
				return priceAvg;
			}
		}
	}

	// Price as of this block according to the assets in the pool
	function ggpSpotPriceInAVAX() public view returns (uint144) {
		(uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();
		return FixedPoint.fraction(uint256(reserve1), uint256(reserve0)).mul(1e18).decode144();
	}

	// Shim so that existing systems can work with this TWAP contract
	function getRateToEth(IERC20 srcToken, bool useSrcWrappers) external view returns (uint256 weightedRate) {
		srcToken; // silence linter
		useSrcWrappers; // silence linter
		weightedRate = ggpTwapPriceInAVAX();
	}

	// helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
	function currentBlockTimestamp() public view returns (uint32) {
		return uint32(block.timestamp % 2 ** 32);
	}

	// produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
	function currentCumulativePrices() public view returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) {
		blockTimestamp = currentBlockTimestamp();
		price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
		price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

		// if time has elapsed since the last update on the pair, mock the accumulated price values
		(uint112 reserve0, uint112 reserve1, uint32 ts) = IUniswapV2Pair(pair).getReserves();
		if (ts != blockTimestamp) {
			// subtraction overflow is desired
			unchecked {
				uint32 timeElapsed = blockTimestamp - ts;
				// * never overflows, and + overflow is desired since we only deal in differences its OK
				price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
				price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
			}
		}
	}
}
