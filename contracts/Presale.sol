// SPDX-License-Identifier: GPL-3.0-or-later Or MIT

pragma solidity ^0.8.0;

import "./Interface8/IERC20.sol";
import "./Interface8/IERC20Metadata.sol";
import "./Interface8/IPancakeRouter02.sol";
import "./Lib8/Ownable.sol";
import "./Lib8/ReentrancyGuard.sol";
import "./Lib8/EnumerableSet.sol";

interface IPancakeFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

interface ILauncher {
    function routers(uint _id) external view returns (address);
}

struct PresaleVesting {
    uint firstRelease;
    uint cycle;
    uint cycleRelease;
}

struct TeamVesting {
    uint total;
    uint firstReleaseDelay;
    uint firstRelease;
    uint cycle;
    uint cycleRelease;
}

struct PresaleData {
    bool isPrivateSale;
    address token;
    uint presale_rate;
    uint softcap;
    uint hardcap;
    uint min;
    uint max;
    uint pcs_liquidity;
    uint pcs_rate;
    uint start_time;
    uint end_time;
    uint unlock_time;
    string title;
    string logo_link;
    string description;
    string metadata;
    address creator;
    address feeAddress;
    uint feeBnbPortion;
    uint feeTokenPortion;
    bool whitelist;
    uint8 refundType;
    uint8 router;
    bool presaleVesting;
    PresaleVesting presaleVestingData;
    bool teamVesting;
    TeamVesting teamVestingData;
    uint collected;
    uint finishedTime;
    bool finished;
    uint cancelTime;
    bool canceled;
    bool isKyc;
    bool isAudit;
    uint contributors;
}

struct Contributes {
    address contributor;
    uint amount;
}

contract Presale is Ownable, ReentrancyGuard {
    // contributors
    mapping(address => uint) public contributes;
    EnumerableSet.AddressSet private _contributors;

    // whitelisted users
    EnumerableSet.AddressSet private _whitelistedUsers;

    // user claims
    mapping(address => uint) private userClaims;

    // presale info
    PresaleData presaleData;
    uint tokenDecimals;
    address public pcsRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    
    // claimed amount of team
    uint claimedTeamVesting = 0;

    // for private sale
    uint claimedFundAmount = 0;

    constructor(PresaleData memory _presale, address _router) {        
        presaleData = _presale;
        pcsRouter = _router;   

        if (_presale.isPrivateSale == false){
            tokenDecimals = IERC20Metadata(presaleData.token).decimals();
        }        
    }

    modifier onlyCreator() {
        require (msg.sender == presaleData.creator, "Access denied");
        _;
    }
    
    function setMetaData(string memory logo_link, string memory description, string memory others) external onlyCreator {
        presaleData.logo_link = logo_link;
        presaleData.description = description;
        presaleData.metadata = others;
    }

    receive() external payable {
        _contribute(msg.sender, msg.value);
    }

    function contribute() payable external {
        _contribute(msg.sender, msg.value);
    }
    
    function _contribute(address user, uint amount) internal {
        require (amount >= presaleData.min && amount <= presaleData.max, "Invalid contribution amount");
        require (block.timestamp >= presaleData.start_time, "Presale is not started yet");
        require (block.timestamp <= presaleData.end_time, "Presale already ended");

        if (presaleData.whitelist) {
            require (isWhitelistedUser(msg.sender), "You're not whitelisted");
        }

        if (!isContributor(user)) {
            _addContributor(user);
        }
        
        uint left = presaleData.hardcap - presaleData.collected;

        uint contributeAmount = amount;
        uint returnAmount = 0;

        if (left <= contributeAmount) {
            returnAmount = contributeAmount - left;
            contributeAmount = left;
        }
        
        uint available = presaleData.max - contributes[user];
        if (contributeAmount > available) {
            returnAmount += contributeAmount - available;
            contributeAmount = available;
        }

        if (returnAmount > 0) {
            payable(user).transfer(returnAmount);
        }
        
        contributes[user] += contributeAmount;
        presaleData.collected += contributeAmount;
    }

    function claim() external nonReentrant {
        require (contributes[msg.sender] > 0, "You have no contributes");
        require (presaleData.finished, "The presale is still active");
        require (presaleData.collected >= presaleData.softcap, "The presale failed");

        uint amount = contributes[msg.sender] * presaleData.presale_rate / (10 ** (18 - tokenDecimals));

        require (amount > userClaims[msg.sender], "You claimed all");

        if (presaleData.presaleVesting) {
            uint claimable = amount * presaleData.presaleVestingData.firstRelease / 100 + amount * (block.timestamp - presaleData.finishedTime) / presaleData.presaleVestingData.cycle * presaleData.presaleVestingData.cycleRelease / 100;

            if (claimable > amount) {
                claimable = amount;
            }

            require (claimable > userClaims[msg.sender], "You cannot claim yet");

            IERC20(presaleData.token).transfer(msg.sender, claimable - userClaims[msg.sender]);

            userClaims[msg.sender] = claimable;

        } else {
            IERC20(presaleData.token).transfer(msg.sender, amount);
            userClaims[msg.sender] = amount;
        }
    }

    function claimFund() external nonReentrant onlyCreator{
        require (presaleData.finished, "The private sale is still active");
        require (presaleData.collected >= presaleData.softcap, "The private sale failed");

        require (presaleData.collected > claimedFundAmount, "You claimed all");

        uint claimable = presaleData.collected * presaleData.presaleVestingData.firstRelease / 100 + 
            presaleData.collected * (block.timestamp - presaleData.finishedTime) / presaleData.presaleVestingData.cycle * presaleData.presaleVestingData.cycleRelease / 100;

        if (claimable > presaleData.collected) {
            claimable = presaleData.collected;
        }

        require (claimable > claimedFundAmount, "You cannot claim yet");

        payable(msg.sender).transfer(claimable - claimedFundAmount);

        claimedFundAmount = claimable;
    }

    function withdraw() external nonReentrant {
        require (contributes[msg.sender] > 0, "You have not contributed");
        require (block.timestamp >= presaleData.end_time, "The presale is still active");
        require (presaleData.collected < presaleData.softcap, "You cannot withdraw now. Claim your tokens instead");

        payable(msg.sender).transfer(contributes[msg.sender]);
        contributes[msg.sender] = 0;
        _delContributor(msg.sender);
    }

    function emergencyWithdraw() external nonReentrant {
        require (contributes[msg.sender] > 0, "You have not contributed");

        payable(msg.sender).transfer(contributes[msg.sender]);
        contributes[msg.sender] = 0;
        _delContributor(msg.sender);
    }

    function finalize() external onlyCreator {
        require (presaleData.collected >= presaleData.softcap, "Presale failed or not ended yet");

        uint feeBnb = presaleData.collected * presaleData.feeBnbPortion / 10000;

        if (presaleData.isPrivateSale) {
            uint claimable = presaleData.collected * presaleData.presaleVestingData.firstRelease / 100;

            if (feeBnb > 0) {
                payable(presaleData.feeAddress).transfer(feeBnb);
            }
            payable(presaleData.creator).transfer(claimable - feeBnb);
            claimedFundAmount = claimable;
        } else {
            uint bnbAmountToLock = (presaleData.collected - feeBnb) * presaleData.pcs_liquidity / 100;
            lockLP(bnbAmountToLock);

            if (feeBnb > 0) {
                payable(presaleData.feeAddress).transfer(feeBnb);
            }
            payable(presaleData.creator).transfer(presaleData.collected - bnbAmountToLock - feeBnb);        
            
            if (presaleData.feeTokenPortion > 0)
                IERC20(presaleData.token).transferFrom(address(this), presaleData.feeAddress, presaleData.collected * presaleData.presale_rate * presaleData.feeTokenPortion / 10**(22-tokenDecimals) );
        }
        
        presaleData.finished = true;
        presaleData.finishedTime = block.timestamp;
    }

    function lockLP(uint bnbAmount) internal {

        uint tokenAmount = bnbAmount * presaleData.pcs_rate;
        IERC20(presaleData.token).approve(address(pcsRouter), tokenAmount);

        IPancakeRouter02(pcsRouter).addLiquidityETH{value: bnbAmount}(
            presaleData.token,
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function unlockLP() external onlyCreator {
        require (block.timestamp >= presaleData.unlock_time, "you need to wait by unlock time");
        address lpToken = IPancakeFactory(IPancakeRouter02(pcsRouter).factory()).getPair(presaleData.token, IPancakeRouter02(pcsRouter).WETH());
        uint256 amount = IERC20(lpToken).balanceOf(address(this));
        if (amount > 0) {
            IERC20(lpToken).transfer(presaleData.creator, amount);
        }        
    }

    function getStatus() view external returns(uint) {
        if (presaleData.collected >= presaleData.hardcap) return 3;
        /** if (block.timestamp > ) ; */
        return 1;
    }
    
    function getClaimAmount(address user) view external returns(uint) {
        if(contributes[user] < 1 || presaleData.collected < presaleData.softcap) return 0;
        uint amount = contributes[user] * presaleData.presale_rate / (10 ** (18 - tokenDecimals));

        if (amount <= userClaims[user]) return 0;

        if (presaleData.presaleVesting) {
            uint claimable = amount * presaleData.presaleVestingData.firstRelease / 100 + amount * (block.timestamp - presaleData.finishedTime) / presaleData.presaleVestingData.cycle * presaleData.presaleVestingData.cycleRelease / 100;

            if (claimable > amount) {
                claimable = amount;
            }

            if (claimable <= userClaims[user]) return 0;

            return claimable - userClaims[user];
        } else {
            return amount;
        }        
    }
    
    function getPrivateSaleClaimAmount() view external returns(uint) {
        if (presaleData.collected < presaleData.softcap) return 0;
        if (presaleData.collected <= claimedFundAmount) return 0;

        uint claimable = presaleData.collected * presaleData.presaleVestingData.firstRelease / 100 + 
            presaleData.collected * (block.timestamp - presaleData.finishedTime) / presaleData.presaleVestingData.cycle * presaleData.presaleVestingData.cycleRelease / 100;

        if (claimable > presaleData.collected) {
            claimable = presaleData.collected;
        }

        if (claimable <= claimedFundAmount) return 0;

        return claimable - claimedFundAmount;       
    }

    function getPresaleData() view public returns(PresaleData memory) {
        return presaleData;
    }

    function addWhitelistUsers(address[] calldata users, bool _whitelisted) external onlyCreator {
        uint i;
        for (i = 0; i < users.length; i+=1) {
            if (_whitelisted){
                _addWhitelistUser(users[i]);
            } else {
                _delWhitelistUser(users[i]);
            }            
        }
    }

    function toggleWhitelist(bool _whitelist) external onlyCreator {
        presaleData.whitelist = _whitelist;
    }

    function claimTeamVesting(address to) external onlyCreator {
        require (presaleData.finished, "The presale is not finished");
        require (claimedTeamVesting < presaleData.teamVestingData.total, "All claimed");

        uint firstReleaseTime = presaleData.finishedTime + presaleData.teamVestingData.firstReleaseDelay;

        require (block.timestamp >= firstReleaseTime, "You can't claim yet");

        uint cycleRelease = presaleData.teamVestingData.total * presaleData.teamVestingData.cycleRelease / 100;

        uint claimableAmount = presaleData.teamVestingData.total * presaleData.teamVestingData.firstRelease / 100 + (block.timestamp - firstReleaseTime) / presaleData.teamVestingData.cycle * cycleRelease - claimedTeamVesting;

        if (claimableAmount + claimedTeamVesting > presaleData.teamVestingData.total) {
            claimableAmount = presaleData.teamVestingData.total - claimedTeamVesting;
        }

        claimedTeamVesting += claimableAmount;

        if (claimableAmount > 0) {
            IERC20(presaleData.token).transfer(payable(to), claimableAmount);
        } 
        
    }

    function cancel() external onlyCreator {
        require (presaleData.canceled == false, "Presale failed or not ended yet");

        presaleData.canceled = true;
        presaleData.cancelTime = block.timestamp;
    }

    function updateKyc(bool _isKyc) external onlyOwner {
        presaleData.isKyc = _isKyc;
    }

    function updateAudit(bool _isAudit) external onlyOwner {
        presaleData.isAudit = _isAudit;
    }


    // contributors functions
    function _addContributor(address _addUser) internal returns (bool) {
        require(_addUser != address(0), "_addUser is the zero address");
        presaleData.contributors++;
        return EnumerableSet.add(_contributors, _addUser);
    }

    function _delContributor(address _delUser) internal returns (bool) {
        require(_delUser != address(0), "_delUser is the zero address");
        presaleData.contributors--;
        return EnumerableSet.remove(_contributors, _delUser);
    }

    function getContributorLength() public view returns (uint256) {
        return EnumerableSet.length(_contributors);
    }

    function getContributor(uint256 _index) public view returns (address){
        require(_index <= getContributorLength() - 1, "index out of bounds");
        return EnumerableSet.at(_contributors, _index);
    }

    function getContributorArr() public view returns (Contributes[] memory) {
        Contributes[] memory contributeArr = new Contributes[](getContributorLength());
        for (uint i = 0; i < getContributorLength(); i+=1) {
            contributeArr[i] = 
                Contributes({
                    contributor: getContributor(i),
                    amount: contributes[getContributor(i)]
                });
        }
        return contributeArr;
    }

    function isContributor(address account) public view returns (bool) {
        return EnumerableSet.contains(_contributors, account);
    }


    // whitelisted users functions
    function _addWhitelistUser(address _addUser) internal returns (bool) {
        require(_addUser != address(0), "_addUser is the zero address");
        return EnumerableSet.add(_whitelistedUsers, _addUser);
    }

    function _delWhitelistUser(address _delUser) internal returns (bool) {
        require(_delUser != address(0), "_delUser is the zero address");
        return EnumerableSet.remove(_whitelistedUsers, _delUser);
    }

    function getWhitelistedUsersLength() public view returns (uint256) {
        return EnumerableSet.length(_whitelistedUsers);
    }

    function getWhitelistedUser(uint256 _index) public view returns (address){
        require(_index <= getWhitelistedUsersLength() - 1, "index out of bounds");
        return EnumerableSet.at(_whitelistedUsers, _index);
    }

    function getWhitelistedUsersArr() public view returns (bytes32[] memory) {
        return _whitelistedUsers._inner._values;
    }

    function isWhitelistedUser(address account) public view returns (bool) {
        return EnumerableSet.contains(_whitelistedUsers, account);
    }
}