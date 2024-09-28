// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Base4626Compounder, Math, ERC20, SafeERC20} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {IReferral} from "./interfaces/ISky.sol";

contract SkyLender is Base4626Compounder {
    using SafeERC20 for ERC20;

    ///@notice Bool if the strategy is open for any depositors. Default = true.
    bool public open = true;
    mapping(address => bool) public allowed; //mapping of addresses allowed to deposit.

    ///@notice yearn's referral code
    uint16 public referral = 13425;

    ///@notice yearn governance
    address public constant GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

    constructor(address _asset, address _vault, string memory _name) Base4626Compounder(_asset, _name, _vault) {
    }

    function _deployFunds(uint256 _amount) internal virtual override {
        IReferral(address(vault)).deposit(_amount, address(this), referral);
        _stake();
    }

    function _freeFunds(uint256 _amount) internal override {
        uint256 shares = vault.previewWithdraw(_amount);

        uint256 vaultBalance = balanceOfVault();
        if (shares > vaultBalance) {
            unchecked {
                _unStake(shares - vaultBalance);
            }
            shares = Math.min(shares, balanceOfVault());
        }

        vault.redeem(shares, address(this), address(this));
    }

    function availableDepositLimit(address _owner) public view override returns (uint256) {
        // If the owner is whitelisted or the strategy is open.
        if (open || allowed[_owner]) {
            return type(uint256).max;
        } else {
            return 0;
        }
    }

    /**
     * @notice Change if anyone can deposit in or only white listed addresses
     * @param _open the bool deciding if anyone can deposit (true) or only whitelisted addresses (false)
     */
    function setOpen(bool _open) external onlyManagement {
        open = _open;
    }

    /**
     * @notice Set or update an addresses whitelist status.
     * @param _address the address for which to change the whitelist status
     * @param _allowed the bool to set as whitelisted (true) or not (false)
     */
    function setAllowed(
        address _address,
        bool _allowed
    ) external onlyManagement {
        allowed[_address] = _allowed;
    }

    /**
     * @notice Set the referral.
     * @param _referral uint16 referral code
     */
    function setReferral(uint16 _referral) external onlyManagement {
        referral = _referral;
    }

    /*//////////////////////////////////////////////////////////////
                GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    /// @notice Sweep of non-asset ERC20 tokens to governance (onlyGovernance)
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external onlyGovernance {
        require(_token != address(asset), "!asset");
        require(_token != address(vault), "!vault");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }

    modifier onlyGovernance() {
        require(msg.sender == GOV, "!gov");
        _;
    }
}