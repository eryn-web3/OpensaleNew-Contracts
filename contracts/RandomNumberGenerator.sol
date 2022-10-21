import "./Interface8/IERC20.sol";
import "./Interface8/IOpensaleFinanceLottery.sol";
import "./Interface8/IRandomNumberGenerator.sol";
import "./Lib8/Ownable.sol";
import "./Lib8/ReentrancyGuard.sol";
import "./Lib8/SafeERC20.sol";
import "./Lib8/VRFConsumerBase.sol";

pragma solidity ^0.8.4;

contract RandomNumberGenerator is VRFConsumerBase, IRandomNumberGenerator, Ownable {
    using SafeERC20 for IERC20;

    address public opensaleFinanceLottery;
    bytes32 public keyHash;
    bytes32 public latestRequestId;
    uint32 public randomResult;
    uint256 public fee;
    uint256 public latestLotteryId;

    /**
     * @notice Constructor
     * @dev RandomNumberGenerator must be deployed before the lottery.
     * Once the lottery contract is deployed, setLotteryAddress must be called.
     * https://docs.chain.link/docs/vrf-contracts/
     * @param _vrfCoordinator: address of the VRF coordinator
     * @param _linkToken: address of the LINK token
     */
    constructor(address _vrfCoordinator, address _linkToken) VRFConsumerBase(_vrfCoordinator, _linkToken) {
        //
    }

    /**
     * @notice Request randomness from a user-provided seed
     * @param _seed: seed provided by the OpensaleFinance lottery
     */
    function getRandomNumber(uint256 _seed) external override {
        require(msg.sender == opensaleFinanceLottery, "Only OpensaleFinanceLottery"); 
        require(keyHash != bytes32(0), "Must have valid key hash");
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK tokens");

        latestRequestId = requestRandomness(keyHash, fee, _seed);
    }

    /**
     * @notice Change the fee
     * @param _fee: new fee (in LINK)
     */
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    /**
     * @notice Change the keyHash
     * @param _keyHash: new keyHash
     */
    function setKeyHash(bytes32 _keyHash) external onlyOwner {
        keyHash = _keyHash;
    }

    /**
     * @notice Set the address for the OpensaleFinanceLottery
     * @param _opensaleFinanceLottery: address of the OpensaleFinance lottery
     */
    function setLotteryAddress(address _opensaleFinanceLottery) external onlyOwner {
        opensaleFinanceLottery = _opensaleFinanceLottery;
    }

    /**
     * @notice It allows the admin to withdraw tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of token amount to withdraw
     * @dev Only callable by owner.
     */
    function withdrawTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);
    }

    /**
     * @notice View latestLotteryId
     */
    function viewLatestLotteryId() external view override returns (uint256) {
        return latestLotteryId;
    }

    /**
     * @notice View random result
     */
    function viewRandomResult() external view override returns (uint32) {
        return randomResult;
    }

    /**
     * @notice Callback function used by ChainLink's VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        require(latestRequestId == requestId, "Wrong requestId");
        randomResult = uint32(1000000 + (randomness % 1000000));
        latestLotteryId = IOpensaleFinanceLottery(opensaleFinanceLottery).viewCurrentLotteryId();
    }
}