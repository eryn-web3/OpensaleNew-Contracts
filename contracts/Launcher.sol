// SPDX-License-Identifier: GPL-3.0-or-later Or MIT

pragma solidity ^0.8.0;

import "./Lib8/Ownable.sol";
import "./Interface8/IERC20Metadata.sol";
import "./Presale.sol";

contract Launcher is Ownable {

    mapping(address => address[]) public ownerToPresales;
    mapping(address => address) public tokenToPresale;
    mapping(address => bool) public isPresale;

    mapping(address => address[]) public ownerToPrivateSales;
    mapping(address => bool) public isPrivateSale;

    uint public feeAmount = 75e16;
    address public feeTo;
    uint public minPresaleTime = 3600;
    uint public maxPresaleTime = 3600 * 24 * 30;

    address[] public routers;

    event PresaleCreated(address owner, address token, address presale, uint start, uint end, uint hardcap, uint softcap, uint lpPercent);
    event PrivateSaleCreated(address owner, address presale, uint start, uint end, uint hardcap, uint softcap);
    
    constructor(address _router) Ownable() {
        feeTo = msg.sender;
        routers.push(_router);
    }

    function createPresale(PresaleData memory _presaleData) payable external {
        require (msg.value >= feeAmount, "Insufficient payment!");
        require (_presaleData.start_time > block.timestamp, "Invalid start time");
        require (_presaleData.end_time >= _presaleData.start_time + minPresaleTime, "Too short presale time");
        require (_presaleData.end_time <= _presaleData.start_time + maxPresaleTime, "Too long presale time");
        require (_presaleData.unlock_time >= _presaleData.end_time, "Invalid unlock time");
        require ( routers[_presaleData.router] != address(0), "Invalid router index");
        
        _presaleData.creator = msg.sender;

        Presale presale = new Presale(_presaleData, routers[_presaleData.router]);
        address presale_address = address(presale);

        if (_presaleData.isPrivateSale == true) {
            ownerToPrivateSales[msg.sender].push(presale_address);
            
            payable(feeTo).transfer(feeAmount);
            if (feeAmount < msg.value) {
                payable(msg.sender).transfer(msg.value - feeAmount);
            }

            isPrivateSale[presale_address] = true;
            
            emit PrivateSaleCreated(msg.sender, presale_address, _presaleData.start_time, _presaleData.end_time, _presaleData.hardcap, _presaleData.softcap);
        } else {
            ownerToPresales[msg.sender].push(presale_address);
            tokenToPresale[_presaleData.token] = presale_address;
            
            uint tokenAmount = 0;
        
            tokenAmount = _calcTokenAmount(_presaleData);
        
            IERC20(_presaleData.token).transferFrom(msg.sender, presale_address, tokenAmount);

            payable(feeTo).transfer(feeAmount);
            if (feeAmount < msg.value) {
                payable(msg.sender).transfer(msg.value - feeAmount);
            }

            isPresale[presale_address] = true;
            
            emit PresaleCreated(msg.sender, _presaleData.token, presale_address, _presaleData.start_time, _presaleData.end_time, _presaleData.hardcap, _presaleData.softcap, _presaleData.pcs_liquidity);
        }
        
    }
    
    function _calcTokenAmount(PresaleData memory presaleData) view internal returns(uint) {
        uint tokenDecimals = IERC20Metadata(presaleData.token).decimals();
        
        uint feeBnbAmount = presaleData.hardcap * presaleData.feeBnbPortion / 10000;
        uint presaleTokenAmount = (10**tokenDecimals) * presaleData.hardcap * presaleData.presale_rate / 1e18;
        uint feeTokenAmount = presaleTokenAmount * presaleData.feeTokenPortion / 10000;
        
        uint lockTokenAmount = (presaleData.hardcap - feeBnbAmount) * presaleData.pcs_liquidity * (10**tokenDecimals) * presaleData.pcs_rate / 1e20;

        uint teamVestingAmount = 0;
        if (presaleData.teamVesting) {
            teamVestingAmount = presaleData.teamVestingData.total;
        }
        
        return presaleTokenAmount + feeTokenAmount + lockTokenAmount + teamVestingAmount;
    }

    // function ownerPresales(address owner) external view returns (address[] memory) {
    //     return ownerToPresales[owner];
    // }

    // function ownerPrivaleSales(address owner) external view returns (address[] memory) {
    //     return ownerToPrivateSales[owner];
    // }

    function updatePresaleKyc(address payable _presale, bool _isKyc, bool _isPrivateSale) external onlyOwner {
        if( _isPrivateSale ) {
            require (isPrivateSale[_presale], "private sale address is not valid");
        } else {
            require (isPresale[_presale], "presale address is not valid");
        }            

        Presale(_presale).updateKyc(_isKyc);
    }

    function updatePresaleAudit(address payable _presale, bool _isAudit, bool _isPrivateSale) external onlyOwner {
        if( _isPrivateSale ) {
            require (isPrivateSale[_presale], "private sale address is not valid");
        } else {
            require (isPresale[_presale], "presale address is not valid");
        }  
        
        Presale(_presale).updateAudit(_isAudit);
    }
    
    function setFee(address _feeTo, uint _feeAmount) external onlyOwner {
        feeTo = _feeTo;
        feeAmount = _feeAmount;
    }
    
    function addRouter(address _router) external {
        routers.push(_router);
    }

}
