// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";
import {IUniswapV2Router02} from "@periphery/interfaces/Uniswap/V2/IUniswapV2Router02.sol";

contract SkyCompounderAprOracleDAI is AprOracleBase {
    constructor() AprOracleBase("SkyCompounder DAI & USDS APR Oracle", 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52) {}
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant secondsPerYear = 31536000;
    address internal constant uniV2router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 router on Mainnet
    
    /**
     * @notice Returns the Sky Rewards Compounding Rate APR.
     */
    function aprAfterDebtChange(
        address /*_strategy*/,
        int256 _delta
    ) external view override returns (uint256) {
        address staking = 0x0650CAF159C5A49f711e8169D4336ECB9b950275;
        address SKY = 0x56072C95FAA701256059aa122697B133aDEd9279;
        address USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
        
        uint256 totalSupply = IStake(staking).totalSupply();
        totalSupply = uint256(int256(totalSupply) + _delta);

        uint256 rewardRate = IStake(staking).rewardRate();
        uint256 price = _getAmountOut(SKY, USDS, WAD);

        uint256 apr = rewardRate * secondsPerYear * price * WAD / totalSupply / WAD;
        return apr;
    }

    function _getAmountOut(
        address _from,
        address _to,
        uint256 _amountIn
    ) internal view virtual returns (uint256) {
        uint256[] memory amounts = IUniswapV2Router02(uniV2router).getAmountsOut(
            _amountIn,
            _getTokenOutPath(_from, _to)
        );

        return amounts[amounts.length - 1];
    }

    function _getTokenOutPath(
        address _tokenIn,
        address _tokenOut
    ) internal view virtual returns (address[] memory _path) {
        _path = new address[](2);
        _path[0] = _tokenIn;
        _path[1] = _tokenOut;
    }
}

interface IStake{
    function rewardRate() external view returns (uint256);
    function totalSupply() external view returns (uint256);
}