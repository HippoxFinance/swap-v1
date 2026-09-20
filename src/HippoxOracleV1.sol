// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {IHippoxSwapPairV1} from "./interfaces/IHippoxSwapPairV1.sol";
/// @title HippoxOracleV1
/// @notice TWAP oracle reader that stores historical cumulative price snapshots
///         and answers queries by `secondsAgo`.
contract HippoxOracleV1 {
    struct Observation {
        uint40 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }
    uint256 public constant MAX_OBSERVATIONS = 64;
    uint40 public constant MIN_ELAPSED_TIME = 30 minutes;
    address public immutable pair;
    Observation[] public observations;
    event ObservationWritten(
        uint40 timestamp,
        uint256 price0Cumulative,
        uint256 price1Cumulative
    );
    constructor(address _pair) {
        require(_pair != address(0), "ZERO_PAIR");
        pair = _pair;
    }
    function observationsLength() external view returns (uint256) {
        return observations.length;
    }
    function update() external {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint40 timestamp
        ) = IHippoxSwapPairV1(pair).getCumulativePrices();
        require(timestamp != 0, "ORACLE_NOT_READY");
        uint256 len = observations.length;
        if (len > 0) {
            Observation memory last = observations[len - 1];
            require(timestamp != last.timestamp, "NO_TIME_ELAPSED");
        }
        if (len >= MAX_OBSERVATIONS) {
            for (uint256 i = 0; i < len - 1; i++) {
                observations[i] = observations[i + 1];
            }
            observations[len - 1] = Observation({
                timestamp: timestamp,
                price0Cumulative: price0Cumulative,
                price1Cumulative: price1Cumulative
            });
        } else {
            observations.push(
                Observation({
                    timestamp: timestamp,
                    price0Cumulative: price0Cumulative,
                    price1Cumulative: price1Cumulative
                })
            );
        }
        emit ObservationWritten(timestamp, price0Cumulative, price1Cumulative);
    }
    function consult(
        address tokenIn,
        uint256 amountIn,
        uint40 secondsAgo
    ) external view returns (uint256 amountOut) {
        require(secondsAgo >= MIN_ELAPSED_TIME, "WINDOW_TOO_SHORT");
        require(observations.length >= 2, "NOT_ENOUGH_OBSERVATIONS");
        (
            uint256 price0CumulativeNow,
            uint256 price1CumulativeNow,
            uint40 timestampNow
        ) = IHippoxSwapPairV1(pair).getCumulativePrices();
        uint40 targetTimestamp = timestampNow - secondsAgo;
        (
            Observation memory before,
            Observation memory after_
        ) = _findObservations(targetTimestamp);
        uint256 price0Cumulative = _interpolate(
            before.timestamp,
            before.price0Cumulative,
            after_.timestamp,
            after_.price0Cumulative,
            targetTimestamp
        );
        uint256 price1Cumulative = _interpolate(
            before.timestamp,
            before.price1Cumulative,
            after_.timestamp,
            after_.price1Cumulative,
            targetTimestamp
        );
        uint256 price0AverageX112 = (price0CumulativeNow - price0Cumulative) /
            secondsAgo;
        uint256 price1AverageX112 = (price1CumulativeNow - price1Cumulative) /
            secondsAgo;
        if (tokenIn == _token0()) {
            amountOut = (amountIn * price0AverageX112) >> 112;
        } else if (tokenIn == _token1()) {
            amountOut = (amountIn * price1AverageX112) >> 112;
        } else {
            revert("INVALID_TOKEN");
        }
    }
    function currentCumulatives()
        external
        view
        returns (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint40 timestamp
        )
    {
        return IHippoxSwapPairV1(pair).getCumulativePrices();
    }
    function _token0() internal view returns (address) {
        return IHippoxSwapPairV1(pair).token0();
    }
    function _token1() internal view returns (address) {
        return IHippoxSwapPairV1(pair).token1();
    }
    function _findObservations(
        uint40 targetTimestamp
    )
        internal
        view
        returns (Observation memory before, Observation memory after_)
    {
        uint256 len = observations.length;
        Observation memory newest = observations[len - 1];
        if (targetTimestamp >= newest.timestamp) {
            return (newest, newest);
        }
        Observation memory oldest = observations[0];
        if (targetTimestamp <= oldest.timestamp) {
            return (oldest, oldest);
        }
        uint256 lo = 0;
        uint256 hi = len - 1;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            if (observations[mid].timestamp <= targetTimestamp) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        after_ = observations[lo];
        before = observations[lo - 1];
    }
    function _interpolate(
        uint40 beforeTimestamp,
        uint256 beforeCumulative,
        uint40 afterTimestamp,
        uint256 afterCumulative,
        uint40 targetTimestamp
    ) internal pure returns (uint256) {
        if (afterTimestamp == beforeTimestamp) {
            return beforeCumulative;
        }
        if (targetTimestamp <= beforeTimestamp) {
            return beforeCumulative;
        }
        if (targetTimestamp >= afterTimestamp) {
            return afterCumulative;
        }
        uint256 timeDelta = uint256(afterTimestamp) - uint256(beforeTimestamp);
        uint256 elapsed = uint256(targetTimestamp) - uint256(beforeTimestamp);
        uint256 cumulativeDelta = afterCumulative - beforeCumulative;
        return beforeCumulative + (cumulativeDelta * elapsed) / timeDelta;
    }
}
