
interface IYEARN {
    function deposit(uint256) external;
    function depositAll() external;
    function withdraw(uint256) external;
    function withdrawAll() external;

    function token() external view returns (address);
    // underlying is only implemented in Delegated Vaults.
    function underlying() external view returns (address);
    function decimals() external view returns (uint8);
    function getPricePerFullShare() external view returns (uint256);


}
