library VaultLib {
    uint256 constant ONE_ONE = 1e36;

    // the collateralization ratio (CR) is checked with the numerator and denominator separately
    // a user is safe if - collateral value >= (COLLAT_RATIO_NUMER/COLLAT_RATIO_DENOM)* debt value
    uint256 public constant CR_NUMERATOR = 3;
    uint256 public constant CR_DENOMINATOR = 2;

    struct Vault {
        // the address that can update the vault
        address operator;
        // uniswap position token id deposited into the vault as collateral
        // 2^32 is 4,294,967,296, which means the vault structure will work with up to 4 billion positions
        uint32 NftCollateralId;
        // amount of eth (wei) used in the vault as collateral
        // 2^96 / 1e18 = 79,228,162,514, which means a vault can store up to 79 billion eth
        // when we need to do calculations, we always cast this number to uint256 to avoid overflow
        uint96 collateralAmount;
        // amount of wPowerPerp minted from the vault
        uint128 shortAmount;
    }
}


interface ISQUEETH {
    
    function deposit(uint256 _vaultId) external payable;
    function withdraw(uint256 _vaultId, uint256 _amount) external payable;
    function redeemShort(uint256 _vaultId) external;
    function depositUniPositionToken(uint256 _vaultId, uint256 _uniTokenId) external;
    function withdrawUniPositionToken(uint256 _vaultId) external;

    function vaults(uint256 _vaultId) external view returns (VaultLib.Vault memory);
    function getExpectedNormalizationFactor() external view returns (uint256);
    function getIndex(uint32 _period) external view returns (uint256);
    function getUnscaledIndex(uint32 _period) external view returns (uint256);
    function getDenormalizedMark(uint32 _period) external view returns (uint256);
    function getDenormalizedMarkForFunding(uint32 _period) external view returns (uint256);
    function shortPowerPerp() external view returns (address);
    function wPowerPerp() external view returns (address);

    function wPowerPerpPool() external view returns (address);

    /**
    *   @dev IMPORTANT: 1.5x is liquidation level for oSQTH!!
    *
    *   collateral value = 0.6 eth
    *   debt value = (debt amount) * (normalization factor) * (eth/usd price)/10000 = 1* 1 * 3000/10000 = 0.3 eth
    *   collateral ratio = 0.6/0.3 = 2 
    *   
    *   https://opyn.gitbook.io/squeeth/contracts/core-contracts/examples/lifecycle-of-a-squeeth
    * */

    function mintPowerPerpAmount(
        uint256 _vaultId,
        uint256 _powerPerpAmount,
        uint256 _uniTokenId
    ) external payable returns (uint256 vaultId, uint256 wPowerPerpAmount);

    function mintWPowerPerpAmount(
        uint256 _vaultId,
        uint256 _wPowerPerpAmount,
        uint256 _uniTokenId
    ) external payable returns (uint256 vaultId);

    function burnPowerPerpAmount(
        uint256 _vaultId,
        uint256 _powerPerpAmount,
        uint256 _withdrawAmount
    ) external returns (uint256 wPowerPerpAmount);

    function burnWPowerPerpAmount(
        uint256 _vaultId,
        uint256 _wPowerPerpAmount,
        uint256 _withdrawAmount
    ) external;


    function getFee(
        uint256 _vaultId,
        uint256 _wPowerPerpAmount,
        uint256 _collateralAmount
    ) external view returns (uint256);



    struct Vault {
        // the address that can update the vault
        address operator;
        // uniswap position token id deposited into the vault as collateral
        // 2^32 is 4,294,967,296, which means the vault structure will work with up to 4 billion positions
        uint32 NftCollateralId;
        // amount of eth (wei) used in the vault as collateral
        // 2^96 / 1e18 = 79,228,162,514, which means a vault can store up to 79 billion eth
        // when we need to do calculations, we always cast this number to uint256 to avoid overflow
        uint96 collateralAmount;
        // amount of wPowerPerp minted from the vault
        uint128 shortAmount;
    }
}
