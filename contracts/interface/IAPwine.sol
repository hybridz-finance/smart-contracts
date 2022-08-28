

interface IAPWINE {

        /**
     * @notice Deposit funds into ongoing period
     * @param _futureVault the address of the futureVault to be deposit the funds in
     * @param _amount the amount to deposit on the ongoing period
     * @dev part of the amount depostied will be used to buy back the yield already generated proportionaly to the amount deposited
     */
    function deposit(address _futureVault, uint256 _amount) external;

    /**
     * @notice Withdraw deposited funds from APWine
     * @param _futureVault the address of the futureVault to withdraw the IBT from
     * @param _amount the amount to withdraw
     */
    function withdraw(address _futureVault, uint256 _amount) external;

        /**
     * @notice Exit a terminated pool
     * @param _futureVault the address of the futureVault to exit from from
     * @param _user the user to exit from the pool
     * @dev only apwibt are required as there  aren't any new FYTs
     */
    function exitTerminatedFuture(address _futureVault, address _user) external;
        /**
     * @notice Getter for the futureVault withdrawals state
     * @param _futureVault the address of the futureVault
     * @return true is new withdrawals are paused, false otherwise
     */
    function isWithdrawalsPaused(address _futureVault) external view returns (bool);
        /**
     * @notice Getter for the futureVault deposits state
     * @param _futureVault the address of the futureVault
     * @return true is new deposits are paused, false otherwise
     */
    function isDepositsPaused(address _futureVault) external view returns (bool);

}
