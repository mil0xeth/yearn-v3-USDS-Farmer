// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Base4626Compounder, Math, ERC20, SafeERC20} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {IReferral} from "./interfaces/ISky.sol";

/// @title yearn-v3-SkyLender
/// @author mil0x
/// @notice yearn v3 Strategy that lends USDS to sUSDS.
contract SkyLender is Base4626Compounder {
    using SafeERC20 for ERC20;

    ///@notice Mapping of addresses that are allowed to deposit.
    mapping(address => bool) public allowed;

    ///@notice yearn's referral code
    uint16 public referral = 13425;

    ///@notice yearn governance
    address public constant GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

    address private constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address private constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;

    constructor(string memory _name) Base4626Compounder(USDS, _name, SUSDS) {
    }

    function _deployFunds(uint256 _amount) internal virtual override {
        IReferral(address(vault)).deposit(_amount, address(this), referral);
    }

    function availableDepositLimit(address _owner) public view override returns (uint256) {
        // If the owner is whitelisted, allow deposits.
        if (allowed[_owner]) {
            return type(uint256).max;
        } else {
            return 0;
        }
    }

    /**
     * @notice Set or update an addresses whitelist status.
     * @param _address the address for which to change the whitelist status
     * @param _allowed the bool to set as whitelisted (true) or not (false)
     */
    function setAllowed(address _address, bool _allowed) external onlyManagement {
        allowed[_address] = _allowed;
    }

    /**
     * @notice Set the referral code for depositing.
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