// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";

contract SkyLenderAprOracle is AprOracleBase {
    constructor() AprOracleBase("SkyLender Universal APR Oracle", 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52) {}
    uint256 internal constant RAY = 1e27;
    uint256 internal constant secondsPerYear = 31536000;
    ISUSDS internal constant SUSDS = ISUSDS(0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD);
    /**
     * @notice Returns the Sky Savings Rate APR. Both parameters do not change the APR.
     */
    function aprAfterDebtChange(
        address /*_strategy*/,
        int256 //_delta //no change in APR according to TVL
    ) external view override returns (uint256) {
        uint256 ssr = SUSDS.ssr(); //in RAY
        return (rpow(ssr, secondsPerYear, RAY) - RAY) / 1e9 + 1; //1e9 converts RAY to WAD
    }

    function rpow(uint x, uint n, uint base) internal pure returns (uint z) {
        assembly {
            switch x case 0 {switch n case 0 {z := base} default {z := 0}}
            default {
                switch mod(n, 2) case 0 { z := base } default { z := x }
                let half := div(base, 2)  // for rounding.
                for { n := div(n, 2) } n { n := div(n,2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0,0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0,0) }
                    x := div(xxRound, base)
                    if mod(n,2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0,0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }
}

interface ISUSDS{
    function ssr() external view returns (uint256);
}