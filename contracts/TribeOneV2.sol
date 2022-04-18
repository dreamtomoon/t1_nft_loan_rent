// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./libraries/Ownable.sol";
import "./interfaces/ITribeOne.sol";
import {ITribeOneAssetGateWay} from "./interfaces/ITribeOneAssetGateWay.sol";
import {IFundingPool} from "./fundingPool/interfaces/IFundingPool.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {ITribeOneAddressesProvider} from "./interfaces/ITribeOneAddressesProvider.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {TribeOneHelper} from "./libraries/TribeOneHelper.sol";
import {TribeOneStorage} from "./TribeOneStorage.sol";
import "./libraries/InterestMath.sol";

abstract contract TribeOneV2 is ERC721Holder, ERC1155Holder, ITribeOne, Ownable, ReentrancyGuard, TribeOneStorage {
    using Counters for Counters.Counter;
    using InterestMath for uint256;
    Counters.Counter public loanIds; // loanId is from No.1

    address public immutable feeCurrency; // stable coin such as USDC, late fee $5
    address public immutable WETH;

    constructor(
        address _salesManager,
        address _feeTo,
        address _feeCurrency,
        address _multiSigWallet,
        address _WETH
    ) {
        require(
            _salesManager != address(0) &&
                _feeTo != address(0) &&
                _feeCurrency != address(0) &&
                _multiSigWallet != address(0),
            "TribeOne: ZERO address"
        );
        salesManager = _salesManager;
        feeTo = _feeTo;
        feeCurrency = _feeCurrency;
        transferOwnership(_multiSigWallet);
        WETH = _WETH;
    }

    receive() external payable {}

    function getAddressesProvider() external view returns (ITribeOneAddressesProvider) {
        return _addressesProvider;
    }

    // TODO check if this view functions is essential
    function getLoanAsset(uint256 _loanId) external view returns (address _token, uint256 _amount) {
        _token = loans[_loanId].loanAsset.currency;
        _amount = loans[_loanId].loanAsset.amount;
    }

    function getLoanRules(uint256 _loanId)
        external
        view
        returns (
            uint16 tenor,
            uint16 LTV,
            uint16 interest
        )
    {
        tenor = loans[_loanId].loanRules.tenor;
        LTV = loans[_loanId].loanRules.LTV;
        interest = loans[_loanId].loanRules.interest;
    }

    function getLoanNFTItems(uint256 _loanId)
        external
        view
        returns (address nftAddress, uint256 nftId, bool isERC721)
    {
        nftAddress = loans[_loanId].nftItem.nftAddress;
        nftId = loans[_loanId].nftItem.nftId;
        isERC721 = loans[_loanId].nftItem.isERC721;
    }

    function setAddressProvider(ITribeOneAddressesProvider _provider) external onlySuperOwner {
        _addressesProvider = _provider;
    }

    function setSettings(
        address _feeTo,
        uint256 _lateFee,
        uint256 _penaltyFee,
        address _salesManager
    ) external onlySuperOwner {
        require(_feeTo != address(0) && _salesManager != address(0), "TribeOne: ZERO address");
        require(_lateFee <= 5 && penaltyFee <= 50, "TribeOne: Exceeded fee limit");
        feeTo = _feeTo;
        lateFee = _lateFee;
        penaltyFee = _penaltyFee;
        salesManager = _salesManager;
        emit SettingsUpdate(_feeTo, _lateFee, _penaltyFee, _salesManager);
    }

    /**
     * @dev _fundAmount shoud be amount in loan currency
     */
    function createLoan(
        uint16[] calldata _loanRules, // tenor, LTV, interest, 10000 - 100% to use array - avoid stack too deep
        address _loanCurrency, // _loanCurrency,  address(0) is native coin
        address nftAddressArray,
        uint256 _fundAmount, // _fundAmount
        uint256 nftTokenIdArray,
        bool isERC721
    ) external payable {
        require(_loanRules.length == 3, "TribeOne: Invalid parameter");
        uint16 tenor = _loanRules[0];
        uint16 LTV = _loanRules[1];
        uint16 interest = _loanRules[2];
        require(LTV > 0, "TribeOne: LTV should not be ZERO");
        require(tenor > 0, "TribeOne: Loan must have at least 1 installment");
        require(
            ITribeOneAssetGateWay(_addressesProvider.getTribeOneAssetGateWay()).isAvailableLoanAsset(_loanCurrency),
            "TribeOne: Loan asset is not available"
        );

        loanIds.increment();
        uint256 loanID = loanIds.current();

        // we will temporarily lock fundAmount here
        if (_loanCurrency == address(0)) {
            require(msg.value >= _fundAmount, "TribeOne: Insufficient fund amount");
        } else {
            TribeOneHelper.safeTransferFrom(_loanCurrency, _msgSender(), address(this), _fundAmount);
        }

        loans[loanID].borrower = _msgSender();
        loans[loanID].loanAsset = Asset({currency: _loanCurrency, amount: 0});
        loans[loanID].loanRules = LoanRules({tenor: tenor, LTV: LTV, interest: interest});
        loans[loanID].fundAmount = uint128(_fundAmount);

        loans[loanID].status = Status.LISTED;
        loans[loanID].nftItem = NFTItem({nftAddress: nftAddressArray, isERC721: isERC721, nftId: nftTokenIdArray});

        emit LoanCreated(loanID, msg.sender);
    }

    function approveLoan(
        uint256 _loanId,
        uint256 _amount,
        address _agent
    ) external override onlyOwner nonReentrant {
        Loan storage _loan = loans[_loanId];
        require(_loan.status == Status.LISTED, "TribeOne: Invalid request");
        require(_agent != address(0), "TribeOne: ZERO address");

        // TODO Combine this validating in one library
        uint256 _fundAmount = _loan.fundAmount;
        uint256 _LTV = _loan.loanRules.LTV;

        uint256 expectedPrice = TribeOneHelper.getExpectedPrice(_fundAmount, _LTV, MAX_SLIPPAGE);
        require(_amount <= expectedPrice, "TribeOne: Invalid amount");

        // Loan should be rejected when requested loan amount is less than fund amount because of some issues such as big fluctuation in marketplace
        if (_amount <= _fundAmount) {
            _loan.status = Status.REJECTED;
            emit LoanRejected(_loanId, _agent);
        } else {
            _loan.status = Status.APPROVED;
            address _token = _loan.loanAsset.currency;

            _loan.loanAsset.amount = _amount - _loan.fundAmount;

            if (_token == address(0)) {
                // This function delivers loan amount to this TrieOne smart contract
                ITribeOneAssetGateWay(_addressesProvider.getTribeOneAssetGateWay()).requestETH(
                    _loan.borrower,
                    _loan.loanRules.interest,
                    _loan.loanAsset.amount
                );
                TribeOneHelper.safeTransferETH(_agent, _amount);
            } else {
                // This function delivers loan amount to this TrieOne smart contract
                ITribeOneAssetGateWay(_addressesProvider.getTribeOneAssetGateWay()).request(
                    _token,
                    _loan.borrower,
                    _loan.loanRules.interest,
                    _loan.loanAsset.amount
                );
                TribeOneHelper.safeTransfer(_token, _agent, _amount);
            }

            emit LoanApproved(_loanId, _agent, _token, _amount);
        }
    }

    /**
     * @dev _loanId: loanId, _accepted: order to Partner is succeeded or not
     * loan will be back to TribeOne if accepted is false
     */
    function relayNFT(
        uint256 _loanId,
        address _agent,
        bool _accepted
    ) external payable override onlyOwner nonReentrant {
        Loan storage _loan = loans[_loanId];
        require(_loan.status == Status.APPROVED, "TribeOne: Not approved loan");
        require(_agent != address(0), "TribeOne: ZERO address");
        if (_accepted) {
            TribeOneHelper.safeTransferNFT(
                _loan.nftItem.nftAddress,
                _agent,
                address(this),
                _loan.nftItem.isERC721,
                _loan.nftItem.nftId
            );

            address _token = _loan.loanAsset.currency;
            if (_token == address(0)) {
                IFundingPool(_addressesProvider.getFundingPool()).borrowETH(
                    _loan.loanAsset.amount,
                    _loan.loanRules.interest,
                    _loan.borrower
                );
            } else {
                // This function delivers loan amount to this TrieOne smart contract
                IFundingPool(_addressesProvider.getFundingPool()).borrow(
                    _token,
                    _loan.loanAsset.amount,
                    _loan.loanRules.interest,
                    _loan.borrower
                );
            }

            _loan.status = Status.LOANACTIVED;
            _loan.loanStart = uint64(block.timestamp);
        } else {
            _loan.status = Status.FAILED;
            // refund loan
            // in the case when loan currency is ETH, loan amount should be fund back from agent to TribeOne AssetNanager
            // fund amount will be back to user
            address _token = _loan.loanAsset.currency;
            uint256 _amount = _loan.loanAsset.amount + _loan.fundAmount;
            if (_token == address(0)) {
                require(msg.value >= _amount, "TribeOne: Less than loan amount");
                if (msg.value > _amount) {
                    TribeOneHelper.safeTransferETH(_agent, msg.value - _amount);
                }
                ITribeOneAssetGateWay(_addressesProvider.getTribeOneAssetGateWay()).refundETH{
                    value: _loan.loanAsset.amount
                }(_loan.borrower, uint256(_loan.loanRules.interest), _loan.loanAsset.amount);
                TribeOneHelper.safeTransferETH(_loan.borrower, _loan.fundAmount);
            } else {
                TribeOneHelper.safeTransferFrom(
                    _token,
                    _agent,
                    _addressesProvider.getTribeOneAssetGateWay(),
                    _loan.loanAsset.amount
                );
                TribeOneHelper.safeTransferFrom(_token, _agent, _loan.borrower, _amount);
                ITribeOneAssetGateWay(_addressesProvider.getTribeOneAssetGateWay()).refund(
                    _loan.borrower,
                    _token,
                    uint256(_loan.loanRules.interest),
                    _loan.loanAsset.amount
                );
            }
        }

        emit NFTRelayed(_loanId, _agent, _accepted);
    }

    function payInstallment(uint256 _loanId, uint256 _amount) external payable nonReentrant {
        Loan storage _loan = loans[_loanId];
        require(_loan.status == Status.LOANACTIVED || _loan.status == Status.DEFAULTED, "TribeOne: Invalid status");
        uint256 expectedNr = expectedNrOfPayments(_loanId);

        address _loanCurrency = _loan.loanAsset.currency;
        if (_loanCurrency == address(0)) {
            _amount = msg.value;
        }

        uint256 paidAmount = _loan.paidAmount;
        uint256 _totalDebt = totalDebt(_loanId); // loan + interest
        {
            uint256 expectedAmount = (_totalDebt * expectedNr) / _loan.loanRules.tenor;
            require(paidAmount + _amount >= expectedAmount, "TribeOne: Insufficient Amount");
            // out of rule, penalty
            _updatePenalty(_loanId);
        }

        uint256 dust;
        if (paidAmount + _amount > _totalDebt) {
            dust = paidAmount + _amount - _totalDebt;
        }
        _amount -= dust;
        // NOTE - don't merge two conditions
        // All user payments will go to FundingPool contract
        if (_loanCurrency == address(0)) {
            if (dust > 0) {
                TribeOneHelper.safeTransferETH(_msgSender(), dust);
            }
            IFundingPool(_addressesProvider.getFundingPool()).repayETH{value: _amount}(
                _msgSender(),
                _loan.loanRules.interest,
                _amount
            );
        } else {
            TribeOneHelper.safeTransferFrom(_loanCurrency, _msgSender(), _addressesProvider.getFundingPool(), _amount);
            IFundingPool(_addressesProvider.getFundingPool()).repay(
                _loanCurrency,
                _msgSender(),
                _loan.loanRules.interest,
                _amount
            );
        }

        _loan.paidAmount += uint128(_amount);
        uint256 passedTenors = (_loan.paidAmount * _loan.loanRules.tenor) / _totalDebt;

        if (passedTenors > _loan.passedTenors) {
            _loan.passedTenors = uint8(passedTenors);
        }

        if (_loan.status == Status.DEFAULTED) {
            _loan.status = Status.LOANACTIVED;
        }

        // If user is borrower and loan is paid whole amount and he has no lateFee, give back NFT here directly
        // else borrower should call withdraw manually himself
        // We should check conditions first to avoid transaction failed
        if (_loan.paidAmount == _totalDebt) {
            _loan.status = Status.LOANPAID;
            if (_loan.nrOfPenalty == 0 || lateFee == 0) {
                _withdrawNFT(_loanId);
            }
        }

        emit InstallmentPaid(_loanId, msg.sender, _loanCurrency, _amount);
    }

    function withdrawNFT(uint256 _loanId) external nonReentrant {
        _withdrawNFT(_loanId);
    }

    function _withdrawNFT(uint256 _loanId) private {
        Loan storage _loan = loans[_loanId];
        require(_loan.status == Status.LOANPAID, "TribeOne: Invalid status - you have still debt to pay");
        address borrower = _loan.borrower;
        _loan.status = Status.WITHDRAWN;

        if (_loan.nrOfPenalty > 0 && lateFee > 0) {
            uint256 _totalLateFee = _loan.nrOfPenalty * lateFee * (10**IERC20Metadata(feeCurrency).decimals());
            TribeOneHelper.safeTransferFrom(feeCurrency, msg.sender, address(feeTo), _totalLateFee);
        }

        TribeOneHelper.safeTransferNFT(
            _loan.nftItem.nftAddress,
            address(this),
            borrower,
            _loan.nftItem.isERC721,
            _loan.nftItem.nftId
        );

        emit NFTWithdrew(_loanId, borrower);
    }

    function _updatePenalty(uint256 _loanId) private {
        Loan storage _loan = loans[_loanId];
        require(_loan.status == Status.LOANACTIVED || _loan.status == Status.DEFAULTED, "TribeOne: Not actived loan");
        uint256 expectedNr = expectedNrOfPayments(_loanId);
        uint256 passedTenors = _loan.passedTenors;
        if (expectedNr > passedTenors) {
            _loan.nrOfPenalty += uint8(expectedNr - passedTenors);
        }
    }

    /**
     * @dev shows loan + interest
     */
    function pendingDebt(uint256 _loanId) external view override returns (uint256) {
        return _pendingDebt(_loanId);
    }

    function _pendingDebt(uint256 _loanId) private view returns (uint256) {
        Loan storage _loan = loans[_loanId];
        return _loan.loanAsset.amount.interestMul(_loan.loanRules.interest) - _loan.paidAmount;
    }

    function totalDebt(uint256 _loanId) public view returns (uint256) {
        Loan storage _loan = loans[_loanId];
        return (_loan.loanAsset.amount * (10000 + _loan.loanRules.interest)) / 10000;
    }

    /**
     *@dev when user in Tenor 2 (from tenor 1 to tenor 2, we expect at least one time payment)
     */
    function expectedNrOfPayments(uint256 _loanId) private view returns (uint256) {
        uint256 loanStart = loans[_loanId].loanStart;
        uint256 _expected = (block.timestamp - loanStart) / TENOR_UNIT;
        uint256 _tenor = loans[_loanId].loanRules.tenor;
        return _expected > _tenor ? _tenor : _expected;
    }

    function expectedLastPaymentTime(uint256 _loanId) public view returns (uint256) {
        Loan storage _loan = loans[_loanId];
        return
            _loan.passedTenors >= _loan.loanRules.tenor
                ? _loan.loanStart + TENOR_UNIT * (_loan.loanRules.tenor)
                : _loan.loanStart + TENOR_UNIT * (_loan.passedTenors + 1);
    }

    function setLoanDefaulted(uint256 _loanId) external nonReentrant {
        Loan storage _loan = loans[_loanId];
        require(_loan.status == Status.LOANACTIVED, "TribeOne: Invalid status");
        require(expectedLastPaymentTime(_loanId) < block.timestamp, "TribeOne: Not overdued date yet");

        _loan.status = Status.DEFAULTED;

        emit LoanDefaulted(_loanId);
    }

    function setLoanLiquidation(uint256 _loanId) external nonReentrant {
        Loan storage _loan = loans[_loanId];
        require(_loan.status == Status.DEFAULTED, "TribeOne: Invalid status");
        require(expectedLastPaymentTime(_loanId) + GRACE_PERIOD < block.timestamp, "TribeOne: Not overdued date yet");
        _loan.status = Status.LIQUIDATION;

        TribeOneHelper.safeTransferNFT(
            _loan.nftItem.nftAddress,
            address(this),
            salesManager,
            _loan.nftItem.isERC721,
            _loan.nftItem.nftId
        );

        emit LoanLiquidation(_loanId, salesManager);
    }

    /**
     * @dev after sold NFT set in market place, and give that fund back to TribeOne
     * TODO check liquidation part
     * Only sales manager can do this
     */
    function postLiquidation(uint256 _loanId, uint256 _amount) external payable nonReentrant {
        require(_msgSender() == salesManager, "TribeOne: Forbidden");
        Loan storage _loan = loans[_loanId];
        require(_loan.status == Status.LIQUIDATION, "TribeOne: invalid status");

        // We collect debts to our asset manager address
        address _currency = _loan.loanAsset.currency;
        _amount = _currency == address(0) ? msg.value : _amount;
        uint256 _finalDebt = finalDebtAndPenalty(_loanId);
        _finalDebt = _amount > _finalDebt ? _finalDebt : _amount;
        // if (_currency == address(0)) {
        //     IFundingPool(_addressesProvider.getFundingPool()).repayETH{value: _finalDebt}(_amount, _msgSender());
        // } else {
        //     TribeOneHelper.safeTransferFrom(_currency, _msgSender(), address(this), _amount);
        //     IFundingPool(_addressesProvider.getFundingPool()).repay(_currency, _amount, _msgSender());
        // }

        _loan.status = Status.POSTLIQUIDATION;
        if (_amount > _finalDebt) {
            _loan.restAmount = uint128(_amount - _finalDebt);
        }
        _loan.postTime = uint64(block.timestamp);
        emit LoanPostLiquidation(_loanId, _amount, _finalDebt);
    }

    function finalDebtAndPenalty(uint256 _loanId) public view returns (uint256) {
        uint256 _debtToPay = _pendingDebt(_loanId);
        return
            (loans[_loanId].status == Status.LIQUIDATION && penaltyFee > 0)
                ? _debtToPay.interestMul(penaltyFee)
                : _debtToPay;
    }

    /**
     * @dev User can get back the rest money through this function, but he should pay late fee.
     */
    function getBackFund(uint256 _loanId) external {
        Loan storage _loan = loans[_loanId];
        require(_msgSender() == _loan.borrower, "TribOne: Forbidden");
        require(_loan.status == Status.POSTLIQUIDATION, "TribeOne: Invalid status");
        require(_loan.postTime + GRACE_PERIOD > block.timestamp, "TribeOne: Time over");
        uint256 _restAmount = _loan.restAmount;
        require(_restAmount > 0, "TribeOne: No amount to give back");

        if (lateFee > 0) {
            uint256 _amount = lateFee * (10**IERC20Metadata(feeCurrency).decimals()) * _loan.nrOfPenalty; // tenor late fee
            TribeOneHelper.safeTransferFrom(feeCurrency, _msgSender(), address(feeTo), _amount);
        }

        _loan.status = Status.RESTWITHDRAWN;

        address _currency = _loan.loanAsset.currency;

        if (_currency == address(0)) {
            TribeOneHelper.safeTransferETH(_msgSender(), _restAmount);
        } else {
            TribeOneHelper.safeTransfer(_currency, _msgSender(), _restAmount);
        }

        emit RestWithdrew(_loanId, _restAmount);
    }

    /**
     * @dev if user does not want to get back rest of money due to some reasons, such as gas fee...
     * we will transfer rest money to our fee address (after 14 days notification).
     * For saving gas fee, we will transfer once for the one kind of token.
     */
    function lockRestAmount(uint256[] calldata _loanIds, address _currency) external nonReentrant {
        uint256 len = _loanIds.length;
        uint256 _amount = 0;
        for (uint256 ii = 0; ii < len; ii++) {
            uint256 _loanId = _loanIds[ii];
            Loan storage _loan = loans[_loanId];
            if (
                _loan.loanAsset.currency == _currency &&
                _loan.status == Status.POSTLIQUIDATION &&
                _loan.postTime + GRACE_PERIOD <= block.timestamp
            ) {
                _amount += _loan.restAmount;
                _loan.status = Status.RESTLOCKED;
            }
        }

        TribeOneHelper.safeTransferAsset(_currency, feeTo, _amount);
    }

    function cancelLoan(uint256 _loanId) external nonReentrant {
        Loan storage _loan = loans[_loanId];
        require(_loan.borrower == _msgSender() && _loan.status == Status.LISTED, "TribeOne: Forbidden");
        _loan.status = Status.CANCELLED;
        emit LoanCanceled(_loanId, _msgSender());
    }

    /**
     * Borrower can sell his loaned NFT item to other man directly by using buyer's signature
     * If loan currency is ETH(address(0)), we will manage this deal based on WETH
     */
    function selfLiquidate(
        uint256 loanId,
        address buyer,
        uint256 price,
        uint256 deadline,
        address collateralToken,
        bytes memory sig
    ) external nonReentrant {
        require(deadline >= block.timestamp, "T1V2: EXPIRED");
        bytes32 msgHash = keccak256(abi.encodePacked(loanId, price, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));

        TribeOneHelper.permit(buyer, digest, sig);

        Loan storage _loan = loans[loanId];
        require(_loan.status == Status.LOANACTIVED, "T1V2: Loan is not actived yet.");
        require(_loan.borrower == msg.sender, "Only borrower can do self-liquidate");

        // Transfer promised price to borrower and fundingPool
        address loanToken = _loan.loanAsset.currency == address(0) ? WETH : _loan.loanAsset.currency;
        TribeOneHelper.safeTransferFrom(loanToken, buyer, address(this), price);

        if (_loan.nrOfPenalty > 0 && lateFee > 0) {
            uint256 _totalLateFee = _loan.nrOfPenalty * lateFee * (10**IERC20Metadata(feeCurrency).decimals());
            TribeOneHelper.safeTransferFrom(feeCurrency, msg.sender, address(feeTo), _totalLateFee);
        }

        uint256 amountToPay = _pendingDebt(loanId);
        if (amountToPay < price) {
            // TODO should consider user gets WETH when loan currency is ETH
            TribeOneHelper.safeTransfer(loanToken, _msgSender(), price - amountToPay);
        } else if (amountToPay > price) {
            ICollateralManager(_addressesProvider.getCollateralManager()).selfLiquidateCollateral(
                collateralToken,
                loanToken,
                msg.sender,
                price - amountToPay
            );
        }

        IFundingPool(_addressesProvider.getFundingPool()).repay(
            loanToken,
            _msgSender(),
            _loan.loanRules.interest,
            amountToPay
        );

        TribeOneHelper.safeTransferNFT(
            _loan.nftItem.nftAddress,
            address(this),
            buyer,
            _loan.nftItem.isERC721,
            _loan.nftItem.nftId
        );
    }
}
