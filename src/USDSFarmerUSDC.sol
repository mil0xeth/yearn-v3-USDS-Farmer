// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {IPSM, IExchange} from "./interfaces/IPSM.sol";
import {IVault} from "./interfaces/IVault.sol";

/// @title yearn-v3-USDS-Farmer-USDC
/// @author mil0x
/// @notice yearn v3 Strategy that trades USDC to USDS to farm 4626 vault.
contract USDSFarmerUSDC is BaseHealthCheck, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    ///@notice Limit for deposits into the strategy to stop strategy TVL to ever grow too large in comparison to the PSM liquidity. In 1e6.
    uint256 public depositLimit; //in 1e6

    ///@notice The 4626 vault for USDS asset to farm.
    address public immutable vault;

    ///@notice Maximum acceptable loss from the investment vault in basis points (default = 0).
    uint256 public maxLossBPS;

    ///@notice Maximum acceptable fee out (DAI to USDC) in WAD units before we use UniswapV3 to swap instead of the PSM. (Default = 5e14 + 1)
    uint256 public maxAcceptableFeeOutPSM; //in WAD

    ///@notice Maximum acceptable swap slippage in case we are swapping through UniswapV3 instead of through PSM. (Depends also on maxAcceptableFeeOutPSM to initiate swap)
    uint256 public swapSlippageBPS; //in BPS
    
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address private constant PSM = 0xf6e72Db5454dd049d0788e411b06CfAF16853042; //LITE-PSM
    address private constant DAI_USDS_EXCHANGER = 0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A;
    address private constant pocket = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;
    address private constant pool = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;
    uint256 private constant SCALER = 1e12;
    uint256 private constant WAD = 1e18;
    uint256 private constant ASSET_DUST = 100;

    constructor(address _asset, address _vault, string memory _name) BaseHealthCheck(_asset, _name) {
        require(IVault(_vault).asset() == USDS, "!asset");
        vault = _vault;
        depositLimit = 100e6 * 1e6; //100M USDC deposit limit to start with
        //use setMaxAcceptableFeeOutPSM(0) to force swap through Uniswap
        maxAcceptableFeeOutPSM = 5e14 + 1; //0.05% expressed in WAD. If the PSM fee out is equal or bigger than this amount, it is probably better to swap through the uniswap pool, accepting slippage.
        swapSlippageBPS = 50; //0.5% expressed in BPS. Allow a slippage of 0.5% for swapping through uniswap.

        // Set uni swapper values
        base = _asset;
        _setUniFees(_asset, DAI, 100);

        //approvals:
        ERC20(_asset).forceApprove(PSM, type(uint).max); //approve the PSM
        ERC20(DAI).forceApprove(PSM, type(uint).max); //approve the PSM
        ERC20(DAI).forceApprove(DAI_USDS_EXCHANGER, type(uint).max); //approve the PSM
        ERC20(USDS).forceApprove(DAI_USDS_EXCHANGER, type(uint).max); //approve the PSM
        ERC20(USDS).forceApprove(vault, type(uint).max);
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function availableDepositLimit(address /*_owner*/) public view override returns (uint256) {
        if (IPSM(PSM).tin() == 0 && IPSM(PSM).tout() == 0) { //only allow deposits if PSM fee in and fee out are 0
            uint256 totalDeposits = TokenizedStrategy.totalAssets();
            if (depositLimit > totalDeposits) {
                return _min(_min(_balancePSM(), IVault(vault).maxDeposit(address(this))) / SCALER, depositLimit - totalDeposits); //minimum of DAI available in PSM, vault maximum deposit, and deposit limit 
            } else {
                return 0;
            }
        } else {
            return 0;
        }
    }

    function _deployFunds(uint256 _amount) internal override {
        _amount = _min(_amount, _balancePSM() / SCALER);
        if (_amount == 0) return;
        IPSM(PSM).sellGem(address(this), _amount); // USDC --> DAI 1:1 through PSM (in USDC amount)
        IExchange(DAI_USDS_EXCHANGER).daiToUsds(address(this), _balanceDAI()); //DAI --> USDS 1:1
        IVault(vault).deposit(_balanceUSDS(), address(this)); //USDS --> vault
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        if (IPSM(PSM).tout() >= maxAcceptableFeeOutPSM) {
            return _balanceAsset() + _min(asset.balanceOf(pool), IVault(vault).maxWithdraw(address(this)) / SCALER); //minimum of UniswapV3 liquidity and vault maximum withdrawable assets
        } else {
            return _balanceAsset() + _min(asset.balanceOf(pocket), IVault(vault).maxWithdraw(address(this)) / SCALER); //minimum of UniswapV3 liquidity and vault maximum withdrawable assets
        }
    }

    function _freeFunds(uint256 _amount) internal override {
        uint256 amountUSDS = _amount * SCALER;
        amountUSDS = _min(amountUSDS, IVault(vault).maxWithdraw(address(this)));
        if (amountUSDS == 0) return;
        if (maxLossBPS == 0) {
            IVault(vault).withdraw(amountUSDS, address(this), address(this)); //vault --> USDS 
        } else {
            IVault(vault).withdraw(amountUSDS, address(this), address(this), maxLossBPS); //vault --> USDS 
        }
        IExchange(DAI_USDS_EXCHANGER).usdsToDai(address(this), _balanceUSDS()); //USDS --> DAI 1:1
        uint256 feeOut = IPSM(PSM).tout(); //in WAD
        if (feeOut >= maxAcceptableFeeOutPSM) { //if PSM fee is not 0
            _swapFrom(DAI, address(asset), _balanceDAI(), _amount * (MAX_BPS - swapSlippageBPS) / MAX_BPS); //swap DAI --> USDC through Uniswap (in DAI amount)
        } else {
            IPSM(PSM).buyGem(address(this), _balanceDAI() * WAD / (WAD + feeOut) / SCALER); // DAI --> USDC 1:1 through PSM (in USDC amount). Need to account for fees that will be added on top.
        }
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        uint256 balance = _balanceAsset();
        if (TokenizedStrategy.isShutdown()) {
            _totalAssets = balance + IVault(vault).convertToAssets(_balanceVault()) / SCALER;
        } else {
            if (balance > ASSET_DUST) {
                _deployFunds(balance);
            }
            _totalAssets = IVault(vault).convertToAssets(_balanceVault()) / SCALER;
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _balancePSM() internal view returns (uint256) {
        return ERC20(DAI).balanceOf(PSM);
    }

    function _balanceAsset() internal view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _balanceDAI() internal view returns (uint256) {
        return ERC20(DAI).balanceOf(address(this));
    }

    function _balanceUSDS() internal view returns (uint256) {
        return ERC20(USDS).balanceOf(address(this));
    }

    function _balanceVault() internal view returns (uint256) {
        return ERC20(vault).balanceOf(address(this));
    }

    /**
     * @notice Set the deposit limit in 1e6 units. Set this to 0 to disallow deposits.
     * @param _depositLimit the deposit limit in 1e6 units
     */
    function setDepositLimit(uint256 _depositLimit) external onlyManagement {
        depositLimit = _depositLimit;
    }

    /**
     * @notice Set the maximum acceptable fee out of the PSM before we automatically switch to Uniswap swapping. Set this to 0 to force swapping through uniswap
     * @param _maxAcceptableFeeOutPSM the maximum fee in WAD (1e18)
     */
    function setMaxAcceptableFeeOutPSM(uint256 _maxAcceptableFeeOutPSM) external onlyManagement {
        require(_maxAcceptableFeeOutPSM <= WAD);
        maxAcceptableFeeOutPSM = _maxAcceptableFeeOutPSM;
    }
    
    /**
     * @notice Set the slippage for deposits in basis points.
     * @param _swapSlippageBPS the maximum slippage in basis points
     */
    function setSwapSlippageBPS(uint256 _swapSlippageBPS) external onlyManagement {
        require(_swapSlippageBPS <= MAX_BPS);
        swapSlippageBPS = _swapSlippageBPS;
    }

    /**
     * @notice Set the maximum loss for withdrawing from the vault in basis points
     * @param _maxLossBPS the maximum loss in basis points
     */
    function setMaxLossBPS(uint256 _maxLossBPS) external onlyManagement {
        require(_maxLossBPS <= MAX_BPS);
        maxLossBPS = _maxLossBPS;
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY
    //////////////////////////////////////////////////////////////*/

    /// @notice In case of an emergencyWithdraw with fees, management needs to call a report right after (ideally bundled).
    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 currentBalance = _balanceVault();
        if (_amount > currentBalance) {
            _amount = currentBalance;
        }
        _freeFunds(IVault(vault).convertToAssets(_amount) / SCALER);
    }
}