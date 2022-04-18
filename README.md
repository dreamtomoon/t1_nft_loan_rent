# TribeOne NFT Loan Smart contract

- TribeOne is the platform which loan digital assets for borrower to purchase NFT items from other partner's platforms.

## Diagram flow
- Borrower requests to create loan with collateral. He can select the type of loan.
- Once loan is requested, admin will approve loan and our agent account buy requested NFT items from Partner's platform and stake it in TribeOne.
  If loan is not valid type, we will notify for use to cancel it.
- Staking NFT items, user should pay installments according to loan rule.
- If user would pay all installment with out any rule out, he can withdraw NFT items and callateral in the final payment.

### Ruled out users
- Once user missed one or any scheduled payment data, we will notify users via email.
- If there's no any reply from user during predefined period(14days for now), we will transfer NFT items to marketplace to sell it. (At that time, we lock collateral forever)
- After selling NFT items in marketplace, our sale manager transfer fund to TribeOne.
- TribeOne will reduce user's debt (loan, interest, penalty, late fee), and notify for user to withdraw the rest, if any. (for predefined period 14days for now)
- If user would not get back in predefined period(14 days), Tribe will lock the rest of money.    

``bash
Note: We set late fee and final penaly as 0 at the first stage.
``

### Deployment
- Once deploying TribeOne, we transfer ownership to MultiSigWallet


### Assets store
  - User
    collateral: TribeOne
    fund amount: TribeOne
    installment payment: Asset Manager
  - Admin
    Asset Manager


### V1 Rinkeby testnet deploy ===
  - TWAP ORACLE FACTORY: 0x6fa8a7E5c13E4094fD4Fa288ba59544791E4c9d3
  - WETH_HAKA 0x953c559c522513b5fc7f806655f16347d465d1f1
  - TWAP_ORACLE WETH_HAKA: 0xcB4e20963ef1B6384126dCeBA8579683a205C5f6
  - TWAP_ORACLE WETH_USDC(0xc778417e063141139fce010982780140aa0cd5ab_0xD4D5c5D939A173b9c18a6B72eEaffD98ecF8b3F6): 0xc86718f161412Ace9c0dC6F81B26EfD4D3A8F5e0

  - MultiSigWallet: 0x153A2FC88aC5EDDBC915A0c3d3c1B86ce8F84842
  - AssetManager: 0x997036a4DC288C7d0C7C570e61dCdb54F0a3d6B2
  - HAKA: 0xd8f50554055Be0276fa29F40Fb3227FE96B5D6c2
  - TribeOne: 0x12335BFD2cCC425e1794b8F53a1d505611d1E2D7
  - AirdropTribeOne: 0x6F971B269B0e3b814529B802F080a27f13721E67

  - new MultiSigWallet 0xca1b4caF38c4449af2183745A00cC3793C2D344c

### Changes from V1
- We will not allow ETH collateral
- No needed automatic loan in TribeOne
- Borrowere health factor: userCollateralInETH / userDebtInETH
- AssetManager become TribeOneAssetGateWay
- Capital will be transferred from AssetManager to TribeOneAssetGateWay in buying NFT staging,
  and after buying staging it would be supplied() from Funding pool and borrower will have debt in FundingPool
- We will define borrower's health factor as total_collateral_capital / total_debt_capital

## Summary of TribeOne V2
We have main contracts, TribeOneV2, CollateralManager, FundingPool, TribeOneAssetGate and BurnManager.
There is a HAKA yield farming smart contract - TribeOneFundingHakaChef additionaly.

### Collateral Manager
- Users should deposit enough collateral(150% over collateralized for his total debt) in advance
- Liquidate collateral.
  We will liquidate some or entire amount of user's collateral under certain condition (TODO: when and how much collateral should be liquidated?)

### TribeOne V2
- Users can create loan and pay installment as same as TribeOne V1 except he should deposit collateral in advance.
Let's see step by step with some comments
- User creates loan
- Admin checks loan and approve it. Here requested fund would be transferred from TribeOneAssetGateWay temporarily.
- Once NFT item is bought successfully, borrow request will be sent to funding pool.
  Spent fund for buying NFT is transferred back to TribeOneAssetGateWay.
  Funding pool status and user's borrowing status is updated based on the intereste rate and borrowing amount.
  NOTE: Borrowing will be validated with some condition. (See below)
- Users pay installments. User's paid fund will be sent to FundingPool and his debt status will be updated
- If user is ruled out(he missed even GRACE PERIOD), related NFT will be liquidated.

### FundingPool
Lenders will deposit funds and will get interest of TribeOne and additional HAKA rewards.
- Lenders will deposit underlying asset(ETH, WETH ...) and will get aToken based on current liquidityIndex and deposit amount.
  Lender's aToken balance shows the share of the lender in funding pool.
  This aToken balance will update HAKA yeild farming, too.
    compoundedLiquidity = compoundedLiquidity + deposit_amount (Look 'Concepts and formulas' for compoundedLiquidity)
- Lenders can withdraw from funding pool based on current compoundedLiquidity and his aToken balance.
    withdraw_amount = compoundedLiquidity * (aToken_amoount / aToken_total_supply)
    compoundedLiquidity = compoundedLiquidity - withdraw_amount
  NOTE: Withdraw should be validated with some rules. (See below)
- Borrowers can borrw fund through TribeOne as mentioned above.
  The compoundedLiquidity and liquidityIndex of fundingPool is updated based on interest rate and borrowed amount.
    compoundedLiquidity1 = compoundedLiquidity0 + (interest_rate * borrowed_amount) 
    liquidityIndex = compoundedLiquidity / aToken_supply
- Borrowers will repay his loan + interest amount through TribeOne
  At that time, we will swap 20% of interest with HAKA and will burn HAKA to keep HAKA price.
  NOTE: 20% values can not be changed once it is set in smart contract. We should set this value very carefully at first time

### Concepts and formulas
- HEALTH_FACTOR_LIMIT: It should be constant, for now 150%
- borrower_health_factor = borrower's_collateral_capital / borrower's_total_debt
- compoundedLiquidity = deposited_amount_in_fundingPool + interest_amount
- liquidityIndex = compoundedLiquidity / aToken_supply
- availableLiquidity: current underlying asset(WETH...) balance of funding pool
- fundgingPool_health_factor = compoundedLiquidity / availableLiquidity
- POOL_HEALTH_FACTOR_LIMIT: ???

### TODO
- Valid pool condition when borrowing/withdrawing from pool besides borrower's health factor checking: 
  Which condition should we use?
  1. utilized_amount(including interest)/availableLiquidity or
  2. fundgingPool_health_factor = compoundedLiquidity / availableLiquidity

#### Liquidation cases
- NFT liqudation 
  Suggestion: It is clear and should be almost same as V1 but I think if the price which we got from marketplace buying liquidated NFT is less than loan(+ interest), some collateral should be liquidated, too.

- Collateral liquidation when under collaterizing.
  Opinion: We should liquidate collateral when borrower's collateral capital is less than 150% of his total debt.
  But we have locked NFT items in TribeOne smart contract, too. In my opinion we should transfer some NFT items to borrower.
  
