// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {ITribeOneAddressesProvider} from "./interfaces/ITribeOneAddressesProvider.sol";
import "./libraries/TribeOneHelper.sol";

contract TribeOneStorage {
    enum Status {
        AVOID_ZERO, // just for avoid zero
        LISTED, // after the loan has been created --> the next status will be APPROVED
        APPROVED, // in this status the loan has a lender -- will be set after approveLoan(). loan fund => borrower
        LOANACTIVED, // NFT was brought from opensea by agent and staked in TribeOne - relayNFT()
        LOANPAID, // loan was paid fully but still in TribeOne
        WITHDRAWN, // the final status, the collateral returned to the borrower or to the lender withdrawNFT()
        FAILED, // NFT buying order was failed in partner's platform such as opensea...
        CANCELLED, // only if loan is LISTED - cancelLoan()
        DEFAULTED, // Grace period = 15 days were passed from the last payment schedule
        LIQUIDATION, // NFT was put in marketplace
        POSTLIQUIDATION, /// NFT was sold
        RESTWITHDRAWN, // user get back the rest of money from the money which NFT set is sold in marketplace
        RESTLOCKED, // Rest amount was forcely locked because he did not request to get back with in 2 weeks (GRACE PERIODS)
        REJECTED // Loan should be rejected when requested loan amount is less than fund amount because of some issues such as big fluctuation in marketplace
    }

    struct Asset {
        uint256 amount;
        address currency; // address(0) is ETH native coin
    }

    struct LoanRules {
        uint16 tenor;
        uint16 LTV; // 10000 - 100%
        uint16 interest; // 10000 - 100%
    }

    struct NFTItem {
        address nftAddress;
        bool isERC721;
        uint256 nftId;
    }

    struct Loan {
        uint128 fundAmount; // the amount which user put in TribeOne to buy NFT
        uint128 paidAmount; // the amount that has been paid back to the lender to date
        uint128 restAmount; // rest amount after sending loan debt(+interest) and 5% penalty
        uint64 loanStart; // the point when the loan is approved
        uint64 postTime; // the time when NFT set was sold in marketplace and that money was put in TribeOne
        address borrower; // the address who receives the loan
        uint8 nrOfPenalty;
        uint8 passedTenors; // the number of tenors which we can consider user passed - paid tenor
        Asset loanAsset;
        Status status; // the loan status
        LoanRules loanRules;
        NFTItem nftItem;
        // address[] nftAddressArray; // the adderess of the NFT token addresses
        // uint256[] nftTokenIdArray; // the unique identifier of the NFT token that the borrower loans
        // TribeOneHelper.TokenType[] nftTokenTypeArray; // the token types : ERC721 , ERC1155 , ...
    }

    mapping(uint256 => Loan) public loans; // loanId => Loan

    ITribeOneAddressesProvider internal _addressesProvider;

    // uint public loanLength;
    uint256 public constant MAX_SLIPPAGE = 500; // 5%
    uint256 public constant TENOR_UNIT = 4 weeks; // installment should be pay at least in every 4 weeks
    uint256 public constant GRACE_PERIOD = 14 days; // 2 weeks

    address public salesManager;
    address public feeTo;

    uint256 public lateFee; // we will set it 5 USD for each tenor late
    uint256 public penaltyFee; // we will set it 5% in the future - 1000 = 100%

    event LoanCreated(uint256 indexed loanId, address indexed owner);
    event LoanApproved(uint256 indexed _loanId, address indexed _to, address _fundCurreny, uint256 _fundAmount);
    event LoanCanceled(uint256 indexed _loanId, address _sender);
    event NFTRelayed(uint256 indexed _loanId, address indexed _sender, bool _accepted);
    event InstallmentPaid(uint256 indexed _loanId, address _sender, address _currency, uint256 _amount);
    event NFTWithdrew(uint256 indexed _loanId, address _to);
    event LoanDefaulted(uint256 indexed _loandId);
    event LoanLiquidation(uint256 indexed _loanId, address _salesManager);
    event LoanPostLiquidation(uint256 indexed _loanId, uint256 _soldAmount, uint256 _finalDebt);
    event RestWithdrew(uint256 indexed _loanId, uint256 _amount);
    event SettingsUpdate(address _feeTo, uint256 _lateFee, uint256 _penaltyFee, address _salesManager);
    event LoanRejected(uint256 _loanId, address _agent);
}
