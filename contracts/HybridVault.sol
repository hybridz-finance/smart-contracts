// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ERC20GasOp.sol";



interface IStrategy{
    function deposit() external;
    function deploy() external;
    function withdraw(uint amount) external;
    function withdrawAll() external;
    function balance() external returns(uint);

    function totalValue() external view returns(uint);
    function forceExit() external returns(uint);
    function gulp(address _token) external;
}


contract Hybrid is ERC20{

    using SafeERC20 for IERC20;
    /*///////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address want;
    address native;
    address owner;

    IStrategy strategy;
    Candidate candidate;


    struct Candidate {
      address strategy;
      uint when;
    }

    /*///////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol

    )ERC20(
        _name,   
        _symbol
    ){
        owner = msg.sender;
    }

    function setStrategy(address _strategy) public {
        require(msg.sender == owner);
        strategy = IStrategy(_strategy);
    }

    /*///////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function withdraw(uint _shares) public {
        uint r = balance() * _shares / totalSupply_;
        _burn(msg.sender, _shares);

        // Check balance
        uint b = balance();
        if (b < r) {
            uint _wAmount = r - b;
            strategy.withdraw(_wAmount);
            uint _after = balance();
            uint _diff = _after - b;
            if (_diff < _wAmount) {
                r = b + _diff;
            }
        }
        IERC20(want).safeTransfer(msg.sender, r);
    }


    function deposit(uint _amount) public {

        IERC20(want).transferFrom(msg.sender,address(this),_amount);

        uint shares = 0;
        if (totalSupply_ == 0) {
            shares = _amount;
        } else {
            shares = _amount * totalSupply_ / poolsize();
        }
        earn();
        _mint(msg.sender, shares);    
    }


    function earn() public {
        IERC20(want).safeTransfer(address(strategy),balance());
        strategy.deploy();
    }


    /*///////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

   
    function balance() internal view returns(uint){
        return IERC20(want).balanceOf(address(this));
    }

    /// figure out how to calculate strategy balance
    function poolsize() internal returns(uint){
        return IERC20(want).balanceOf(address(this))
        + strategy.balance();
    }


    /*///////////////////////////////////////////////////////////////
                           PUBLIC VIEWS
    //////////////////////////////////////////////////////////////*/

    function getPricePerFullShare() public view returns (uint) {
        return balance() * 1e18 / totalSupply_;
    }












}