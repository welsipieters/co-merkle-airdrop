// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.14;

import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { Counters } from "@openzeppelin/contracts/utils/Counters.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";

error AlreadyClaimed(uint256, address);
error IncorrectAllocation(uint256, uint256, address, uint256);
error NoAdminRole(address);
error DepositFailed(address, address, uint256);
error ClaimUnbegun(uint256);
error ClaimEnded(uint256);


/// @title A ERC-20 token distributor based on a Merkle tree.
/// @author Wesley Peeters <wesley.peeters@corite.com>
contract MerkleDistributor is AccessControl {
    using Counters for Counters.Counter;

    /// ---------- Structs ----------
    struct Campaign {
        uint id;
        IERC20 token;
        uint256 claimedAmount;
        uint256 totalAmount;
        uint256 claimStart;
        uint256 claimEnd;
        bytes32 root;
        mapping(uint256 => uint256) claimedMap;
    }

    /// ---------- Immutable storage ----------
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    /// ---------- Mutable Storage ----------
    Counters.Counter public campaignCount;

    mapping(uint256 => Campaign) public campaigns;


    /// ---------- Constructor ----------
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
    }

    /// ---------- Modifiers ----------



    /// ---------- Events ----------

    /// @notice Emitted after a successful claim.
    /// @param to: The recipient of the tokens.
    /// @param amount: The amount of tokens that were claimed.
    event Claim(uint256 id, address indexed to, uint256 amount);

    /// @notice Emitted after an admin deposited tokens into the contract for distribution.
    /// @param token: The address of the deposited token. If this address is `0x0`, the deposited currency was chain-native.
    /// @param amount: The amount of the token that was deposited.
    event TokensDeposited(address token, uint256 amount);

    /// @notice Emitted after an admin withdraws tokens from the contract.
    /// @param token: The address of the withdrawn token. If this address is `0x0`, the withdrawn currency was chain-native.
    /// @param to: The recipient of the tokens.
    /// @param amount: The amount of tokens that were withdrawn.
    event TokensWithdrawnFromContract(address token, address indexed to, uint256 amount);

    event CampaignCreated(uint256 id, address token, uint256 amount, uint256 start, uint256 end, bytes32 root);

    /// @notice Emitted after an admin updates a campaign.
    /// @param root: The new Merkle root.
    event CampaignUpdated(uint256 id, uint256 start, uint256 end, bytes32 root);

    /// @notice Emitted after an admin updates the address of the token that users can claim.
    /// @param newToken: The address of the token that can now be claimed.
    event DistributorTokenUpdated(address newToken);

    /// ---------- Methods ----------

    /// @notice Deposit ERC20 tokens into the contract.
    /// @param _token: The token to deposit.
    /// @param _amount: The amount of tokens to deposit.
    function deposit(IERC20 _token, uint256 _amount) external onlyRole(ADMIN_ROLE) {
        if (!_token.transferFrom(msg.sender, address(this), _amount)) {
            revert DepositFailed(msg.sender, address(_token), _amount);
        }

        emit TokensDeposited(address(_token), _amount);
    }

    /// @notice External function to withdraw leftover ERC20 tokens on the contract.
    /// @param _token: The address of the token to withdraw.
    /// @param _to: The recipient of the tokens.
    /// @param _amount: The amount of tokens to withdraw.
    function withdrawErc20(address _token, address _to, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_amount == 0) {
            _amount = IERC20(_token).balanceOf(address(this));
        }

        _withdrawErc20(_token, _to, _amount);

        emit TokensWithdrawnFromContract(_token, _to, _amount);
    }

    /// @notice External function to withdraw ETH (or any other native currency) on the contract.
    /// @param _to: The recipient of the ETH.
    /// @param _amount: The amount of ETH to withdraw.
    function withdrawEth(address _to, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_amount == 0) {
            _amount = address(this).balance;
        }

        TransferHelper.safeTransferETH(_to, _amount);

        emit TokensWithdrawnFromContract(address(0x0), _to, _amount);
    }

    /// @notice Function that checks if a user has claimed their allocation based on their index in the allocation list.
    /// @param _index: The index of the user in the allocation.
    function hasClaimed(uint256 _id, uint256 _index) public view returns (bool) {
        Campaign storage campaign = campaigns[_id];

        uint256 group = campaign.claimedMap[_index / 256];
        uint256 mask = (uint256(1) << uint256(_index % 256));

        return ((group & mask) != 0);
    }

    /// @notice Function that allows claiming if the caller is part of the allocation Merkle tree.
    /// @param _index: The index of the user in the allocation.
    /// @param _amount: The amount of tokens to be claimed.
    /// @param _proof: Merkle proof to prove sender address & amount are in the tree.
    function claim(uint256 _id, uint256 _index, uint256 _amount, bytes32[] calldata _proof) external {
        Campaign storage campaign = campaigns[_id];

        if (campaign.claimStart > block.timestamp) {
            revert ClaimUnbegun(_id);
        }

        if (block.timestamp > campaign.claimEnd) {
            revert ClaimEnded(_id);
        }

        uint256 group = campaign.claimedMap[_index / 256];
        uint256 mask = (uint256(1) << uint256(_index % 256));

        if ((group & mask) != 0) {
            revert AlreadyClaimed(_id, msg.sender);
        }

        /// Set to claimed
        campaign.claimedMap[_index / 256] = group | mask;
        campaign.claimedAmount += _amount;

        bytes32 leaf = keccak256(abi.encodePacked(_index, msg.sender, _amount));
        if (!MerkleProof.verify(_proof, campaign.root, leaf)) {
            revert IncorrectAllocation(_id, _index, msg.sender, _amount);
        }

        _withdrawErc20(address(campaign.token), msg.sender, _amount);

        emit Claim(_id, msg.sender, _amount);
    }

    /// @notice Just wanna be sure in case someone accidentally sends eth.
    /// @notice We like free eth.
    receive() external payable {
        emit TokensDeposited(address(0x0), msg.value);
    }

    function createCampaign(IERC20 _token, uint256 _amount, uint256 _claimStart, uint256 _claimEnd, bytes32 _root) external onlyRole(ADMIN_ROLE) returns (uint256 _id) {
        _id = campaignCount.current();
        campaignCount.increment();

        Campaign storage campaign = campaigns[_id];
        campaign.id = _id;
        campaign.token = _token;
        campaign.totalAmount = _amount;
        campaign.claimStart = _claimStart;
        campaign.claimEnd = _claimEnd;
        campaign.root = _root;

        emit CampaignCreated(_id, address(_token), _amount, _claimStart, _claimEnd, _root);
    }

    function editCampaign(uint256 _id, uint256 _start, uint256 _end, bytes32 _root) external onlyRole(ADMIN_ROLE) {
        Campaign storage campaign = campaigns[_id];
        campaign.claimStart = _start;
        campaign.claimEnd = _end;
        campaign.root = _root;

        emit CampaignUpdated(_id, _start, _end, _root);
    }

    /// ---------- Internal Methods ----------

    /// @notice INTERNAL method to withdraw ERC20 tokens.
    /// @param _token: The address of the token to withdraw.
    /// @param _to: The recipient of the tokens.
    /// @param _amount: The amount of tokens to withdraw.
    function _withdrawErc20(address _token, address _to, uint256 _amount) internal {
        TransferHelper.safeTransfer(_token, _to, _amount);
    }
}
