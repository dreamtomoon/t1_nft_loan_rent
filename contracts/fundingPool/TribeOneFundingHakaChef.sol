// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ITribeOneAddressesProvider} from "../interfaces/ITribeOneAddressesProvider.sol";
import "../libraries/TribeOneHelper.sol";

import "hardhat/console.sol";

/**
 * @dev We control funding pools here and implement yield farming, too.
 */

contract TribeOneFundingHakaChef is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Info of each TribeOneFundingPool user.
    /// `amount` FToken amount the user has provided.
    /// `rewardDebt` The amount of HAKA entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
    }

    /// @notice Info of each TribeOneLendingPool pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of HAKA to distribute per block.
    struct PoolInfo {
        uint128 accHakaPerShare;
        uint64 lastRewardBlock;
        uint64 allocPoint;
        uint256 totalSupply;
    }

    EnumerableSet.AddressSet private _assets;
    mapping(address => PoolInfo) private poolInfo;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => mapping(address => UserInfo)) public userInfo; // pool_asset => user_address => userInfo

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    uint256 private constant ACC_HAKA_PRECISION = 1e12;

    uint256 public hakaPerBlock;
    address public immutable HAKA;
    ITribeOneAddressesProvider private _addressesProvider;

    event Deposit(address indexed user, address indexed _asset, uint256 amount, address indexed to);
    event Withdraw(address indexed to, address indexed _asset, uint256 amount);
    event EmergencyWithdraw(address indexed user, address indexed _asset, uint256 amount, address indexed to);
    event Harvest(address indexed user, address indexed _asset, uint256 pending, uint256 harvested);
    event LogPoolAddition(uint256 allocPoint, address indexed token);
    event LogSetPool(address indexed _asset, uint256 allocPoint);
    event LogUpdatePool(address indexed _asset, uint64 lastRewardBlock, uint256 lpSupply, uint256 accHakaPerShare);

    constructor(
        uint256 _hakaPerBlock,
        address _HAKA,
        ITribeOneAddressesProvider _provider
    ) {
        hakaPerBlock = _hakaPerBlock;
        HAKA = _HAKA;
        _addressesProvider = _provider;
    }

    modifier onlyFundingPool() {
        require(msg.sender == _addressesProvider.getFundingPool(), "Only FundingPool");
        _;
    }

    function setHakaPerBlock(uint256 _hakaPerBlock) external onlyOwner {
        require(_hakaPerBlock != hakaPerBlock, "It is current value");
        massUpdatePools();
        hakaPerBlock = _hakaPerBlock;
    }

    function setAddressProvider(ITribeOneAddressesProvider _provider) external onlyOwner {
        _addressesProvider = _provider;
    }

    function getAddressProvider() external view returns (address) {
        return address(_addressesProvider);
    }

    /// @notice Add a new asset to the pool. Can only be called by the owner.
    /// @param allocPoint AP of the new pool. 100 - 1 point
    /// @param _asset Address of the LP ERC-20 token.
    function add(uint256 allocPoint, address _asset) external onlyFundingPool {
        require(_asset != address(0), "TribeOneFundingHakaChef: ZERO address");
        require(!_assets.contains(_asset), "Already added");
        massUpdatePools();

        _assets.add(_asset);
        totalAllocPoint = totalAllocPoint + allocPoint;

        poolInfo[_asset] = PoolInfo({
            allocPoint: uint64(allocPoint),
            lastRewardBlock: uint64(block.number),
            accHakaPerShare: 0,
            totalSupply: 0
        });
        emit LogPoolAddition(allocPoint, _asset);
    }

    /// @notice Update the given pool's HAKA allocation point.
    /// @param _asset The asset of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    function set(address _asset, uint256 _allocPoint) external onlyOwner {
        require(_assets.contains(_asset), "Not valid pool");
        require(poolInfo[_asset].allocPoint != _allocPoint, "It is current value");

        massUpdatePools();

        totalAllocPoint = totalAllocPoint - poolInfo[_asset].allocPoint + _allocPoint;
        poolInfo[_asset].allocPoint = uint64(_allocPoint);
        emit LogSetPool(_asset, _allocPoint);
    }

    /// @notice View function to see pending HAKA on frontend.
    /// @param _asset The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending HAKA reward for a given user.
    function pendingHaka(address _asset, address _user) external view returns (uint256 pending) {
        PoolInfo storage pool = poolInfo[_asset];
        UserInfo storage user = userInfo[_asset][_user];

        uint256 accHakaPerShare = pool.accHakaPerShare;
        uint256 totalSupply = pool.totalSupply;

        if (block.number > pool.lastRewardBlock && totalSupply != 0) {
            uint256 blocks = block.number - pool.lastRewardBlock;
            uint256 hakaReward = (blocks * hakaPerBlock * pool.allocPoint) / totalAllocPoint;
            accHakaPerShare = accHakaPerShare + ((hakaReward * ACC_HAKA_PRECISION) / totalSupply);
        }
        pending = user.pendingRewards + (user.amount * accHakaPerShare) / ACC_HAKA_PRECISION - uint256(user.rewardDebt);
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 len = _assets.length(); //_assets.length;
        for (uint256 i = 0; i < len; ++i) {
            _updatePool(_assets.at(i));
        }
    }

    function updatePool(address _asset) external nonReentrant {
        _updatePool(_asset);
    }

    /// @notice Update reward variables of the given pool.
    /// @param _asset The index of the pool. See `poolInfo`.
    function _updatePool(address _asset) private {
        PoolInfo storage pool = poolInfo[_asset];
        if (block.number > pool.lastRewardBlock) {
            uint256 totalSupply = pool.totalSupply;
            if (totalSupply > 0) {
                uint256 blocks = block.number - pool.lastRewardBlock;
                uint256 hakaReward = (blocks * hakaPerBlock * pool.allocPoint) / totalAllocPoint;
                pool.accHakaPerShare = pool.accHakaPerShare + uint128((hakaReward * ACC_HAKA_PRECISION) / totalSupply);
            }
            pool.lastRewardBlock = uint64(block.number);
            poolInfo[_asset] = pool;
            emit LogUpdatePool(_asset, pool.lastRewardBlock, totalSupply, pool.accHakaPerShare);
        }
    }

    /// @param amount LP token amount to deposit. If amount = 0, it means user wants to harvest
    /// @param _asset The index of the pool. See `poolInfo`.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(
        uint256 amount,
        address _asset,
        address to
    ) external onlyFundingPool {
        PoolInfo storage pool = poolInfo[_asset];

        UserInfo storage user = userInfo[_asset][to];
        _updatePool(_asset);

        if (amount > 0) {
            user.amount += amount;

            user.rewardDebt = user.rewardDebt + (amount * pool.accHakaPerShare) / ACC_HAKA_PRECISION;
        }

        emit Deposit(msg.sender, _asset, amount, to);
    }

    /// @param _asset The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    function withdraw(
        address _asset,
        address _to,
        uint256 amount
    ) external onlyFundingPool {
        PoolInfo storage pool = poolInfo[_asset];
        UserInfo storage user = userInfo[_asset][_to];
        _updatePool(_asset);
        _harvest(_asset, _to);

        if (amount > 0) {
            user.amount = user.amount - amount;
        }
        user.rewardDebt = (user.amount * pool.accHakaPerShare) / ACC_HAKA_PRECISION;

        emit Withdraw(_to, _asset, amount);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param _asset The index of the pool. See `poolInfo`.
    /// @param to Receiver of HAKA rewards.
    function _harvest(address _asset, address to) private {
        PoolInfo storage pool = poolInfo[_asset];
        UserInfo storage user = userInfo[_asset][to];

        // harvest current reward
        uint256 pending = user.pendingRewards +
            (user.amount * pool.accHakaPerShare) /
            ACC_HAKA_PRECISION -
            user.rewardDebt;
        user.pendingRewards = pending;
        uint256 rewardBal = IERC20(HAKA).balanceOf(address(this));
        uint256 harvested = pending > rewardBal ? rewardBal : pending;
        if (harvested > 0) {
            TribeOneHelper.safeTransfer(HAKA, to, harvested);
            user.pendingRewards -= harvested;
        }

        emit Harvest(to, _asset, pending, harvested);
    }

    function harvest(address _asset) external {
        _harvest(_asset, msg.sender);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param _asset The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(address _asset, address to) external nonReentrant {
        UserInfo storage user = userInfo[_asset][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, _asset, amount, to);
    }

    function withdrawAsset(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        if (_token == address(0)) {
            TribeOneHelper.safeTransferETH(_to, _amount);
        } else {
            TribeOneHelper.safeTransfer(_token, _to, _amount);
        }
    }
}
