// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IExchange} from "./interfaces/IPSM.sol";
import {IVault} from "./interfaces/IVault.sol";

/// @title yearn-v3-USDS-Farmer-DAI
/// @author mil0x
/// @notice yearn v3 Strategy that trades DAI to USDS to farm 4626 vault.
contract USDSFarmerDAI is BaseHealthCheck {
    using SafeERC20 for ERC20;

    ///@notice The 4626 vault for USDS asset to farm.
    address public immutable vault;
    
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address private constant DAI_USDS_EXCHANGER = 0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A;
    uint256 private constant ASSET_DUST = 100;

    constructor(address _vault, string memory _name) BaseHealthCheck(DAI, _name) {
        require(IVault(_vault).asset() == USDS, "!asset");
        vault = _vault;

        //approvals:
        ERC20(DAI).forceApprove(DAI_USDS_EXCHANGER, type(uint).max); //approve the PSM
        ERC20(USDS).forceApprove(DAI_USDS_EXCHANGER, type(uint).max); //approve the PSM
        ERC20(USDS).forceApprove(vault, type(uint).max);
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function availableDepositLimit(address /*_owner*/) public view virtual override returns (uint256) {
        return IVault(vault).maxDeposit(address(this));
    }

    function _deployFunds(uint256 _amount) internal override {
        IExchange(DAI_USDS_EXCHANGER).daiToUsds(address(this), _amount); //DAI --> USDS 1:1
        IVault(vault).deposit(_amount, address(this)); //USDS --> vault
    }

    function availableWithdrawLimit(address) public view virtual override returns (uint256) {
        return _balanceAsset() + _vaultsMaxWithdraw();
    }

    function _vaultsMaxWithdraw() internal view returns (uint256) {
        return IVault(vault).convertToAssets(IVault(vault).maxRedeem(address(this)));
    }

    function _freeFunds(uint256 _amount) internal override {
        uint256 shares = IVault(vault).previewWithdraw(_amount);
        shares = _min(shares, _balanceVault());
        IExchange(DAI_USDS_EXCHANGER).usdsToDai(address(this), IVault(vault).redeem(shares, address(this), address(this))); //vault --> USDS -- 1:1 --> DAI
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        uint256 balance = _balanceAsset();
        if (TokenizedStrategy.isShutdown()) {
            _totalAssets = balance + IVault(vault).convertToAssets(_balanceVault());
        } else {
            balance = _min(balance, availableDepositLimit(address(this)));
            if (balance > ASSET_DUST) {
                _deployFunds(balance);
            }
            _totalAssets = IVault(vault).convertToAssets(_balanceVault());
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _balanceAsset() internal view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _balanceUSDS() internal view returns (uint256) {
        return ERC20(USDS).balanceOf(address(this));
    }

    function _balanceVault() internal view returns (uint256) {
        return ERC20(vault).balanceOf(address(this));
    }

    /**
     * @notice Deploy any donations of USDS.
     */
    function deployDonations() external onlyManagement {
        IVault(vault).deposit(_balanceUSDS(), address(this)); //USDS --> vault
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraw funds from the vault into the strategy in an emergency.
     * @param _amount the amount of asset to emergencyWithdraw into the strategy
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(_min(_amount, _vaultsMaxWithdraw()));
    }
}