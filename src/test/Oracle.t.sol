pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

import {StrategyAprOracle} from "../periphery/StrategyAprOracle.sol";

contract OracleTest is Setup {
    StrategyAprOracle public oracle;

    function setUp() public override {
        super.setUp();
        oracle = new StrategyAprOracle();
    }

    function checkOracle(address _strategy) public {
        // Check set up
        // TODO: Add checks for the setup

        uint256 currentApr = oracle.aprAfterDebtChange(_strategy, 0);
        console.log("currentApr: ", currentApr);
        // Should be greater than 0 but likely less than 100%
        assertGe(currentApr, 6 * 1e16, "Not more than 6% APR");
        assertLt(currentApr, 20 * 1e16, "Not less than 20% APR");
    }

    function test_oracle_single() public {
        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        console.log("currentApr: ", currentApr);
        assertGe(currentApr, 6 * 1e16, "Not more than 6% APR");
        assertLt(currentApr, 20 * 1e16, "Not less than 20% APR");
    }

    function test_oracle(uint256 _amount, uint16 _percentChange) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _percentChange = uint16(bound(uint256(_percentChange), 10, MAX_BPS));

        mintAndDepositIntoStrategy(strategy, user, _amount);

        checkOracle(address(strategy));
    }

}