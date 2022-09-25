// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.14;

import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";

error AlreadyClaimed(address);
error IncorrectAllocation(uint256, address, uint256);
error NoAdminRole(address);
error DepositFailed(address, address, uint256);

/// @title A ERC-20 token distributor based on a Merkle tree.
/// @author Wesley Peeters <wesley.peeters@corite.com>
contract MerkleDistributor is AccessControl {
    /// ---------- Immutable storage ----------
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// ---------- Mutable Storage ----------

    /// @notice Root including all the claimee's for the token.
    bytes32 public merkleRoot;

    /// @notice Mapping of what index already claimed their tokens.
    mapping(uint256 => uint256) public claimedMap;

    /// @notice Token that users can claim.
    IERC20 public claimableToken;

    /// ---------- Constructor ----------

    /// @param _merkleRoot: The Merkle root generated based on the addresses and allocations for users.
    constructor(bytes32 _merkleRoot) {
        _setupRole(ADMIN_ROLE, msg.sender);

        merkleRoot = _merkleRoot;
    }

    /// ---------- Modifiers ----------

    /// @notice Basic modifier incorporating ACL.
    modifier adminOnly() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) {
            revert NoAdminRole(msg.sender);
        }

        _;
    }

    /// ---------- Events ----------

    /// @notice Emitted after a successful claim.
    /// @param to: The recipient of the tokens.
    /// @param amount: The amount of tokens that were claimed.
    event Claim(address indexed to, uint256 amount);

    /// @notice Emitted after an admin deposited tokens into the contract for distribution.
    /// @param token: The address of the deposited token. If this address is `0x0`, the deposited currency was chain-native.
    /// @param amount: The amount of the token that was deposited.
    event TokensDeposited(address token, uint256 amount);

    /// @notice Emitted after an admin withdraws tokens from the contract.
    /// @param token: The address of the withdrawn token. If this address is `0x0`, the withdrawn currency was chain-native.
    /// @param to: The recipient of the tokens.
    /// @param amount: The amount of tokens that were withdrawn.
    event TokensWithdrawnFromContract(address token, address indexed to, uint256 amount);

    /// @notice Emitted after an admin updates the allocation Merkle root.
    /// @param newRoot: The new Merkle root.
    event MerkleRootUpdated(bytes32 newRoot);

    /// @notice Emitted after an admin updates the address of the token that users can claim.
    /// @param newToken: The address of the token that can now be claimed.
    event DistributorTokenUpdated(address newToken);

    /// ---------- Methods ----------

    /// @notice Change the token that users can claim.
    /// @param _claimable: The address of the new token users can now claim.
    function setClaimable(IERC20 _claimable) external adminOnly {
        claimableToken = _claimable;

        emit DistributorTokenUpdated(address(_claimable));
    }

    /// @notice Change the allocation Merkle root.
    /// @param _root: The new allocation Merkle root.
    function setMerkleRoot(bytes32 _root) external adminOnly {
        merkleRoot = _root;

        emit MerkleRootUpdated(_root);
    }

    /// @notice Deposit ERC20 tokens into the contract.
    /// @param _token: The token to deposit.
    /// @param _amount: The amount of tokens to deposit.
    function deposit(IERC20 _token, uint256 _amount) external adminOnly {
        if (!_token.transferFrom(msg.sender, address(this), _amount)) {
            revert DepositFailed(msg.sender, address(_token), _amount);
        }

        emit TokensDeposited(address(_token), _amount);
    }

    /// @notice External function to withdraw leftover ERC20 tokens on the contract.
    /// @param _token: The address of the token to withdraw.
    /// @param _to: The recipient of the tokens.
    /// @param _amount: The amount of tokens to withdraw.
    function withdrawErc20(address _token, address _to, uint256 _amount) external adminOnly {
        if (_amount == 0) {
            _amount = IERC20(_token).balanceOf(address(this));
        }

        _withdrawErc20(_token, _to, _amount);

        emit TokensWithdrawnFromContract(_token, _to, _amount);
    }

    /// @notice External function to withdraw ETH (or any other native currency) on the contract.
    /// @param _to: The recipient of the ETH.
    /// @param _amount: The amount of ETH to withdraw.
    function withdrawEth(address _to, uint256 _amount) external adminOnly {
        if (_amount == 0) {
            _amount = address(this).balance;
        }

        TransferHelper.safeTransferETH(_to, _amount);

        emit TokensWithdrawnFromContract(address(0x0), _to, _amount);
    }

    /// @notice Function that checks if a user has claimed their allocation based on their index in the allocation list.
    /// @param _index: The index of the user in the allocation.
    function hasClaimed(uint256 _index) public view returns (bool) {
        uint256 group = claimedMap[_index / 256];
        uint256 mask = (uint256(1) << uint256(_index % 256));

        return ((group & mask) != 0);
    }

    /// @notice Function that allows claiming if the caller is part of the allocation Merkle tree.
    /// @param _index: The index of the user in the allocation.
    /// @param _amount: The amount of tokens to be claimed.
    /// @param _proof: Merkle proof to prove sender address & amount are in the tree.
    function claim(uint256 _index, uint256 _amount, bytes32[] calldata _proof) external {
        uint256 group = claimedMap[_index / 256];
        uint256 mask = (uint256(1) << uint256(_index % 256));

        if ((group & mask) != 0) {
            revert AlreadyClaimed(msg.sender);
        }

        /// Set to claimed
        claimedMap[_index / 256] = group | mask;

        bytes32 leaf = keccak256(abi.encodePacked(_index, msg.sender, _amount));
        if (!MerkleProof.verify(_proof, merkleRoot, leaf)) {
            revert IncorrectAllocation(_index, msg.sender, _amount);
        }

        _withdrawErc20(address(claimableToken), msg.sender, _amount);

        emit Claim(msg.sender, _amount);
    }

    /// @notice Just wanna be sure in case someone accidentally sends eth.
    /// @notice We like free eth.
    receive() external payable {
        emit TokensDeposited(address(0x0), msg.value);
    }


    /// ---------- Internal Methods ----------

    /// @notice INTERNAL method to withdraw ERC20 tokens.
    /// @param _token: The address of the token to withdraw.
    /// @param _to: The recipient of the tokens.
    /// @param _amount: The amount of tokens to withdraw.
    function _withdrawErc20(address _token, address _to, uint256 _amount) internal {
        TransferHelper.safeApprove(_token, _to, _amount);
        TransferHelper.safeTransfer(_token, _to, _amount);
    }
}
