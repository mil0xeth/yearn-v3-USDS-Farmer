pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {SetupDAI} from "./utils/SetupDAI.sol";

import {SkyLenderAprOracle} from "../periphery/SkyLenderAprOracle.sol";
import {SkyCompounderAprOracleDAI} from "../periphery/SkyCompounderAprOracleDAI.sol";
import {SkyCompounderAprOracleUSDC} from "../periphery/SkyCompounderAprOracleUSDC.sol";

contract OracleTest is SetupDAI {
    SkyLenderAprOracle public oracle;
    SkyCompounderAprOracleDAI public compounderOracleDAI;
    SkyCompounderAprOracleUSDC public compounderOracleUSDC;
    uint256 SCALER = 1e12;

    function setUp() public override {
        super.setUp();
        oracle = new SkyLenderAprOracle();
        compounderOracleDAI = new SkyCompounderAprOracleDAI();
        compounderOracleUSDC = new SkyCompounderAprOracleUSDC();
    }

    function checkSkyLenderOracle(address _strategy) public {
        uint256 currentApr = oracle.aprAfterDebtChange(_strategy, 0);
        console.log("currentApr: ", currentApr);
        // Should be greater than 0 but likely less than 100%
        assertGe(currentApr, 6 * 1e16, "Not more than 6% APR");
        assertLt(currentApr, 20 * 1e16, "Not less than 20% APR");
    }

    function checkSkyComppounderOracleDAI(address _strategy) public {
        uint256 currentApr = compounderOracleDAI.aprAfterDebtChange(_strategy, 0);
        console.log("currentApr: ", currentApr);
        // Should be greater than 0 but likely less than 100%
        assertGe(currentApr, 6 * 1e16, "Not more than 6% APR");
        assertLt(currentApr, 20 * 1e16, "Not less than 20% APR");
    }

    function checkSkyComppounderOracleUSDC(address _strategy) public {
        uint256 currentApr = compounderOracleUSDC.aprAfterDebtChange(_strategy, 0);
        console.log("currentApr: ", currentApr);
        // Should be greater than 0 but likely less than 100%
        assertGe(currentApr, 6 * 1e16, "Not more than 6% APR");
        assertLt(currentApr, 20 * 1e16, "Not less than 20% APR");
    }

    function test_SkyLender_oracle_single() public {
        uint256 currentApr = oracle.aprAfterDebtChange(address(strategy), 0);
        console.log("currentApr: ", currentApr);
        assertGe(currentApr, 6 * 1e16, "Not more than 6% APR");
        assertLt(currentApr, 20 * 1e16, "Not less than 20% APR");
    }

    function test_SkyCompounderDAI_oracle_single() public {
        uint256 currentApr = compounderOracleDAI.aprAfterDebtChange(address(strategy), 0);
        //uint256 currentApr = compounderOracleDAI.aprAfterDebtChange(address(strategy), 100e6 * 1e18);
        console.log("currentApr: ", currentApr);
        assertGe(currentApr, 6 * 1e16, "Not more than 6% APR");
        assertLt(currentApr, 20 * 1e16, "Not less than 20% APR");
    }

    function test_SkyCompounderUSDC_oracle_single() public {
        uint256 currentApr = compounderOracleUSDC.aprAfterDebtChange(address(strategy), 0);
        //uint256 currentApr = compounderOracleUSDC.aprAfterDebtChange(address(strategy), 100e6 * 1e6);
        console.log("currentApr: ", currentApr);
        assertGe(currentApr, 6 * 1e16, "Not more than 6% APR");
        assertLt(currentApr, 20 * 1e16, "Not less than 20% APR");
    }

    function test_SkyLender_oracle(uint256 _amount, uint16 _percentChange) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _percentChange = uint16(bound(uint256(_percentChange), 10, MAX_BPS));
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkSkyLenderOracle(address(strategy));
    }

    function test_SkyCompounderDAI_oracle(uint256 _amount, uint16 _percentChange) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _percentChange = uint16(bound(uint256(_percentChange), 10, MAX_BPS));
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkSkyComppounderOracleDAI(address(strategy));
    }

    function test_SkyCompounderUSDC_oracle(uint256 _amount, uint16 _percentChange) public {
        vm.assume(_amount > minFuzzAmount / SCALER && _amount < maxFuzzAmount / SCALER);
        _percentChange = uint16(bound(uint256(_percentChange), 10, MAX_BPS));
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkSkyComppounderOracleUSDC(address(strategy));
    }

}