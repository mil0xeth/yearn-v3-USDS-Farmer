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

    ///@notice Maximum acceptable loss from the investment vault in basis points (default = 0).
    uint256 public maxLossBPS;
    
    address private constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address private constant DAI_USDS_EXCHANGER = 0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A;
    uint256 private constant WAD = 1e18;
    uint256 private constant ASSET_DUST = 100;

    constructor(address _asset, address _vault, string memory _name) BaseHealthCheck(_asset, _name) {
        require(IVault(_vault).asset() == USDS, "!asset");
        vault = _vault;

        //approvals:
        ERC20(_asset).forceApprove(DAI_USDS_EXCHANGER, type(uint).max); //approve the PSM
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
        return _balanceAsset() + IVault(vault).maxWithdraw(address(this)) + 2; //2 wei rounding errors are possible due to investment vault
    }

    function _freeFunds(uint256 _amount) internal override {
        _amount = _min(_amount, IVault(vault).maxWithdraw(address(this)));
        if (_amount == 0) return;
        if (maxLossBPS == 0) {
            IVault(vault).withdraw(_amount, address(this), address(this)); //vault --> USDS 
        } else {
            IVault(vault).withdraw(_amount, address(this), address(this), maxLossBPS); //vault --> USDS 
        }
        IExchange(DAI_USDS_EXCHANGER).usdsToDai(address(this), _balanceUSDS()); //USDS --> DAI 1:1
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        uint256 balance = _balanceAsset();
        if (TokenizedStrategy.isShutdown()) {
            _totalAssets = balance + IVault(vault).convertToAssets(_balanceVault());
        } else {
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
        _freeFunds(IVault(vault).convertToAssets(_amount));
    }
}