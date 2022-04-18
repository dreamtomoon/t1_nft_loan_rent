// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStableDebtToken} from "../interfaces/IStableDebtToken.sol";
import {FPBaseToken} from "./base/FPBaseToken.sol";
import {IFundingPool} from "../interfaces/IFundingPool.sol";
import {IAToken} from "../interfaces/IAToken.sol";
import {WadRayMath} from "../libraries/math/WadRayMath.sol";

/**
 * @title FundingPool ERC20 AToken
 * @dev Implementation of the interest bearing token for the FundingPool protocol
 */
contract AToken is IAToken, FPBaseToken {
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    IFundingPool internal _pool;
    address internal _underlyingAsset;

    uint256 public burnToAmount;

    bool public initialized;

    /**
     * @dev Initializes the aToken
     * @param pool The address of the lending pool where this aToken will be used
     * @param underlyingAsset The address of the underlying asset of this aToken (E.g. WETH for aWETH)
     * @param aTokenDecimals The decimals of the aToken, same as the underlying asset's
     * @param aTokenName The name of the aToken
     * @param aTokenSymbol The symbol of the aToken
     */
    function initialize(
        IFundingPool pool,
        address underlyingAsset,
        uint8 aTokenDecimals,
        string calldata aTokenName,
        string calldata aTokenSymbol
    ) external override {
        require(!initialized, "AToken: Initialized already");
        initialized = true;
        _setName(aTokenName);
        _setSymbol(aTokenSymbol);
        _setDecimals(aTokenDecimals);

        _pool = pool;
        _underlyingAsset = underlyingAsset;

        emit Initialized(underlyingAsset, address(pool), aTokenDecimals, aTokenName, aTokenSymbol);
    }

    /**
     * @dev Burns aTokens from `user` and sends the equivalent amount of underlying to `receiverOfUnderlying`
     * - Only callable by the FundingPool, as extra state updates there need to be managed
     * @param user The owner of the aTokens, getting them burned
     * @param receiverOfUnderlying The address that will receive the underlying
     * @param amount The amount being burned
     * @param index The new liquidity index of the reserve
     **/
    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 amount,
        uint256 index
    ) external override onlyFundingPool returns (uint256) {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "AToken: Invalid amount");
        _burn(user, amountScaled);

        IERC20(_underlyingAsset).safeTransfer(receiverOfUnderlying, amount);

        emit Burn(user, receiverOfUnderlying, amountScaled, index);

        return amountScaled;
    }

    /**
     * @dev Mints `amount` aTokens to `user`
     * - Only callable by the FundingPool, as extra state updates there need to be managed
     * @param user The address receiving the minted tokens
     * @param amount The amount of tokens getting minted
     * @param index The new liquidity index of the reserve
     * @return `true` if the the previous balance of the user was 0
     */
    function mint(
        address user,
        uint256 amount,
        uint256 index
    ) external override onlyFundingPool returns (uint256) {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "AToken: Invalid amount");
        _mint(user, amountScaled);

        emit Mint(user, amountScaled, index);

        return amountScaled;
    }

    function compoundedLiquidity() external view override returns (uint256) {
        address debtTokenAddress = _pool.getReserveData(_underlyingAsset).stableDebtTokenAddress;
        return
            IERC20(_underlyingAsset).balanceOf(address(this)) +
            IStableDebtToken(debtTokenAddress).compoundedTotalSupply();
    }

    /**
     * TODO trying to manage interest burn here
     */
    function handleRepayment(uint256 _burnToAmount) external override onlyFundingPool {
        burnToAmount += _burnToAmount;
    }

    /**
     * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
     **/
    function UNDERLYING_ASSET_ADDRESS() public view override returns (address) {
        return _underlyingAsset;
    }

    /**
     * @dev Returns the address of the lending pool where this aToken is used
     **/
    function POOL() public view returns (IFundingPool) {
        return _pool;
    }

    /**
     * @dev Transfers the underlying asset to `target`. Used by the FundingPool to transfer
     * assets in borrow(), withdraw()
     * @param target The recipient of the aTokens
     * @param amount The amount getting transferred
     * @return The amount transferred
     **/
    function transferUnderlyingTo(address target, uint256 amount) external override onlyFundingPool returns (uint256) {
        IERC20(_underlyingAsset).safeTransfer(target, amount);
        return amount;
    }

    /**
     * @dev For internal usage in the logic of the parent contracts
     **/
    function _getFundingPool() internal view override returns (IFundingPool) {
        return _pool;
    }

    /**
     * @dev For internal usage in the logic of the parent contracts
     **/
    function _getUnderlyingAssetAddress() internal view override returns (address) {
        return _underlyingAsset;
    }
}
