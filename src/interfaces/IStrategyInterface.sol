// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {

    function reportTrigger(
        address _strategy
    ) external view returns (bool, bytes memory);

    function balanceAsset() external view returns (uint256);
    function balanceSUSDS() external view returns (uint256);

    function setProfitLimitRatio(uint256) external;
    function setLossLimitRatio(uint256) external;
    function setDepositLimit(uint256) external;
    function setDoHealthCheck(bool) external;
    function setMaxAcceptableFeeOutPSM(uint256) external;
    function setProfitMaxUnlockTime(uint256) external;
    function setMaxLossBPS(uint256) external;
    function setMinAmountToSell(uint256) external;
}