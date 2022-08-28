// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;


interface IMasterChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function enterStaking(uint256 _amount) external;
    function leaveStaking(uint256 _amount) external;
    function userInfo(uint _pid, address _user) external view returns (uint256, uint256);
    function getUserInfo(uint _pid) external view returns (uint);
    function emergencyWithdraw(uint256 _pid) external;
}
