const { ethers } = require('hardhat');

const WETH = {
  rinkeby: '0xc778417e063141139fce010982780140aa0cd5ab'
};

const USDC = {
  rinkeby: '0xD4D5c5D939A173b9c18a6B72eEaffD98ecF8b3F6'
};

const HAKA = {
  rinkeby: '0xd8f50554055Be0276fa29F40Fb3227FE96B5D6c2'
};

const TWAP_ORACLE_PRICE_FEED_WETH_USDC = {
  rinkeby: '0xc86718f161412Ace9c0dC6F81B26EfD4D3A8F5e0'
};

const MAX_STABLE_RATE_BORROW_SIZE_PERCENT = 2500;

module.exports = {
  WETH,
  USDC,
  TWAP_ORACLE_PRICE_FEED_WETH_USDC,
  HAKA,
  MAX_STABLE_RATE_BORROW_SIZE_PERCENT
};
