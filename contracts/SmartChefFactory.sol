// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Interface8/IERC20Metadata.sol";
import "./Lib8/Ownable.sol";
import "./SmartChefInitializable.sol";


contract SmartChefFactory is Ownable {
    event NewSmartChefContract(address indexed smartChef);

    constructor() {
        //
    }

    /*
     * @notice Deploy the pool
     * @param _stakedToken: staked token address
     * @param _rewardToken: reward token address
     * @param _rewardPerBlock: reward per block (in rewardToken)
     * @param _startBlock: start block
     * @param _endBlock: end block
     * @param _poolLimitPerUser: pool limit per user in stakedToken (if any, else 0)
     * @param _numberBlocksForUserLimit: block numbers available for user limit (after start block)
     * @param _opensaleProfile: Opensale Profile address
     * @param _opensaleProfileIsRequested: Opensale Profile is requested
     * @param _opensaleProfileThresholdPoints: Opensale Profile need threshold points
     * @param _admin: admin address with ownership
     * @return address of new smart chef contract
     */
    function deployPool(
        IERC20Metadata _stakedToken,
        IERC20Metadata _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _poolLimitPerUser,
        uint256 _numberBlocksForUserLimit,
        address _opensaleProfile,
        bool _opensaleProfileIsRequested,
        uint256 _opensaleProfileThresholdPoints,
        address _admin
    ) external onlyOwner {
        require(_stakedToken.totalSupply() >= 0);
        require(_rewardToken.totalSupply() >= 0);
        require(_stakedToken != _rewardToken, "Tokens must be be different");

        bytes memory bytecode = type(SmartChefInitializable).creationCode;
        // pass constructor argument
        bytecode = abi.encodePacked(
            bytecode,
            abi.encode(_opensaleProfile, _opensaleProfileIsRequested, _opensaleProfileThresholdPoints)
        );
        bytes32 salt = keccak256(abi.encodePacked(_stakedToken, _rewardToken, _startBlock));
        address smartChefAddress;

        assembly {
            smartChefAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        SmartChefInitializable(smartChefAddress).initialize(
            _stakedToken,
            _rewardToken,
            _rewardPerBlock,
            _startBlock,
            _bonusEndBlock,
            _poolLimitPerUser,
            _numberBlocksForUserLimit,
            _admin
        );

        emit NewSmartChefContract(smartChefAddress);
    }
}