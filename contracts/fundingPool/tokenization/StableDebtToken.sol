// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {FPBaseToken} from "./base/FPBaseToken.sol";
import {MathUtils} from "../libraries/math/MathUtils.sol";
import {WadRayMath} from "../libraries/math/WadRayMath.sol";
import {IStableDebtToken} from "../interfaces/IStableDebtToken.sol";
import {IFundingPool} from "../interfaces/IFundingPool.sol";

/**
 * @title StableDebtToken
 * @notice Implements a stable debt token to track the borrowing positions of users
 * at stable rate mode
 **/
contract StableDebtToken is IStableDebtToken, FPBaseToken {
    using WadRayMath for uint256;

    // using SafeMath for uint256;

    IFundingPool internal _pool;
    address internal _underlyingAsset;

    bool public initialized;

    uint256 private _compoundedTotalSupply;
    mapping(address => uint256) private _compoundedBalanceOf;

    function compoundedTotalSupply() external view override returns (uint256) {
        return _compoundedTotalSupply;
    }

    function compoundedBalanceOf(address _account) external view override returns (uint256) {
        return _compoundedBalanceOf[_account];
    }

    /**
     * @dev Initializes the debt token.
     * @param pool The address of the lending pool where this aToken will be used
     * @param underlyingAsset The address of the underlying asset of this aToken (E.g. WETH for aWETH)
     * @param debtTokenDecimals The decimals of the debtToken, same as the underlying asset's
     * @param debtTokenName The name of the token
     * @param debtTokenSymbol The symbol of the token
     */
    function initialize(
        IFundingPool pool,
        address underlyingAsset,
        uint8 debtTokenDecimals,
        string memory debtTokenName,
        string memory debtTokenSymbol
    ) public override {
        require(!initialized, "SD: Initialized already");
        initialized = true;
        _setName(debtTokenName);
        _setSymbol(debtTokenSymbol);
        _setDecimals(debtTokenDecimals);

        _pool = pool;
        _underlyingAsset = underlyingAsset;

        emit Initialized(underlyingAsset, address(pool), debtTokenDecimals, debtTokenName, debtTokenSymbol);
    }

    /**
     * @dev Mints debt token to the `onBehalfOf` address.
     * -  Only callable by the FundingPool
     * - The resulting rate is the weighted average between the rate of the new debt
     * and the rate of the previous debt
     * @param user The address receiving the borrowed underlying, being the delegatee in case
     * of credit delegate, or same as `onBehalfOf` otherwise
     * @param amount The amount of debt tokens to mint
     * @param rate The rate of the debt being minted
     **/
    function mint(
        address user,
        uint256 amount,
        uint256 rate
    ) external override onlyFundingPool returns (bool) {
        uint256 currentBalance = balanceOf(user);
        uint256 balanceIncrease = (amount * rate) / 10000;
        _mint(user, amount + balanceIncrease);

        // compounded balance
        uint256 compoundedIncrease = calculateCompoundedAmount(balanceIncrease);
        _compoundedBalanceOf[user] += (amount + compoundedIncrease);
        _compoundedTotalSupply += (amount + compoundedIncrease);

        emit Mint(user, amount, rate, balanceIncrease, compoundedIncrease);
        return currentBalance == 0;
    }

    /**
     * @dev Burns debt of `user`
     * @param user The address of the user getting his debt burned
     * @param amount The amount of debt tokens getting burned
     * @param interestAmountToBurn The amount to burn from interest
     **/
    function burn(
        address user,
        uint256 amount,
        uint256 interestAmountToBurn
    ) external override onlyFundingPool {
        uint256 currentBalance = balanceOf(user);

        uint256 previousSupply = totalSupply();

        // Since the total supply and each single user debt accrue separately,
        // there might be accumulation errors so that the last borrower repaying
        // mght actually try to repay more than the available debt supply.
        // In this case we simply set the total supply and the avg stable rate to 0
        if (previousSupply <= amount) {
            _totalSupply = 0;
        }

        _burn(user, amount);

        _compoundedBalanceOf[user] -= (amount - interestAmountToBurn);
        _compoundedTotalSupply -= (amount - interestAmountToBurn);

        emit Burn(user, amount, currentBalance);
    }

    function calculateCompoundedAmount(uint256 balanceIncrease) private view returns (uint256) {
        uint256 burnToAmount = (balanceIncrease * _pool.getInterestBurnPercentage()) / 10000;
        return (balanceIncrease - burnToAmount);
    }

    /**
     * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
     **/
    function UNDERLYING_ASSET_ADDRESS() public view returns (address) {
        return _underlyingAsset;
    }

    /**
     * @dev Returns the address of the funding pool where this aToken is used
     **/
    function POOL() public view returns (IFundingPool) {
        return _pool;
    }

    /**
     * @dev For internal usage in the logic of the parent contracts
     **/
    function _getUnderlyingAssetAddress() internal view override returns (address) {
        return _underlyingAsset;
    }

    /**
     * @dev For internal usage in the logic of the parent contracts
     **/
    function _getFundingPool() internal view override returns (IFundingPool) {
        return _pool;
    }
}
