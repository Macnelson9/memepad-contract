// use starknet::ContractAddress;

// use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

// use memeforge::launchPad::IMemeCoinLaunchpadDispatcher;
// use memeforge::launchPad::IMemeCoinLaunchpadDispatcherTrait;
// use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

// fn deploy_contract(name: ByteArray) -> ContractAddress {
//     let contract = declare(name).unwrap().contract_class();
//     let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
//     contract_address
// }


// fn deploy_launchpad(
//     name: felt252,
//     symbol: felt252,
//     initial_supply: u256,
//     curve_factor: u256,
//     owner: ContractAddress
// ) -> ContractAddress {
//     let contract = declare("MemeCoinLaunchpad").unwrap().contract_class();
//     let mut constructor_calldata = ArrayTrait::new();
//     constructor_calldata.append(name);
//     constructor_calldata.append(symbol);
//     constructor_calldata.append(initial_supply.low.into());
//     constructor_calldata.append(initial_supply.high.into());
//     constructor_calldata.append(curve_factor.low.into());
//     constructor_calldata.append(curve_factor.high.into());
//     constructor_calldata.append(owner.into());
//     let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
//     contract_address
// }

// #[test]
// fn test_launchpad_constructor() {
//     let owner: ContractAddress = 0x123.try_into().unwrap();
//     let contract_address = deploy_launchpad('MemeCoin', 'MEME', 1000000_u256, 1000000_u256, owner);

//     let dispatcher = IMemeCoinLaunchpadDispatcher { contract_address };

//     let price = dispatcher.get_current_price();
//     assert(price == 1000000_u256 * 1000000_u256, 'Invalid initial price');

//     // Check initial balance of owner
//     let erc20_dispatcher = IERC20Dispatcher { contract_address };
//     let balance = erc20_dispatcher.balance_of(owner);
//     assert(balance == 1000000_u256, 'Invalid initial balance');
// }

// #[test]
// fn test_buy_tokens() {
//     let owner: ContractAddress = 0x123.try_into().unwrap();
//     let buyer: ContractAddress = 0x456.try_into().unwrap();
//     let contract_address = deploy_launchpad('MemeCoin', 'MEME', 1000000_u256, 1000000_u256, owner);

//     let dispatcher = IMemeCoinLaunchpadDispatcher { contract_address };

//     // Simulate buying tokens
//     dispatcher.buy_tokens(1000000000000_u256); // amount_in = price

//     let erc20_dispatcher = IERC20Dispatcher { contract_address };
//     let balance = erc20_dispatcher.balance_of(buyer);
//     assert(balance == 1_u256, 'Invalid bought amount');

//     let price_after = dispatcher.get_current_price();
//     assert(price_after == 1000001000000_u256, 'Invalid price after buy');
// }

// #[test]
// fn test_sell_tokens() {
//     let owner: ContractAddress = 0x123.try_into().unwrap();
//     let seller: ContractAddress = 0x456.try_into().unwrap();
//     let contract_address = deploy_launchpad('MemeCoin', 'MEME', 1000000_u256, 1000000_u256, owner);

//     let dispatcher = IMemeCoinLaunchpadDispatcher { contract_address };
//     let erc20_dispatcher = IERC20Dispatcher { contract_address };

//     // First buy some tokens
//     dispatcher.buy_tokens(1000000000000_u256);
//     let balance_before_sell = erc20_dispatcher.balance_of(seller);
//     assert(balance_before_sell == 1_u256, 'Invalid balance before sell');

//     // Now sell
//     dispatcher.sell_tokens(1_u256);

//     let balance_after_sell = erc20_dispatcher.balance_of(seller);
//     assert(balance_after_sell == 0_u256, 'Invalid balance after sell');

//     let price_after = dispatcher.get_current_price();
//     assert(price_after == 1000000000000_u256, 'Invalid price after sell');
// }

// #[test]
// #[should_panic(expected: ('Amount must be positive',))]
// fn test_buy_tokens_insufficient_output() {
//     let owner: ContractAddress = 0x123.try_into().unwrap();
//     let buyer: ContractAddress = 0x456.try_into().unwrap();
//     let contract_address = deploy_launchpad('MemeCoin', 'MEME', 1000000_u256, 1000000_u256, owner);

//     let dispatcher = IMemeCoinLaunchpadDispatcher { contract_address };

//     dispatcher.buy_tokens(0_u256); // Should panic
// }

// #[test]
// #[should_panic(expected: ('Tokens must be positive',))]
// fn test_sell_tokens_insufficient_output() {
//     let owner: ContractAddress = 0x123.try_into().unwrap();
//     let seller: ContractAddress = 0x456.try_into().unwrap();
//     let contract_address = deploy_launchpad('MemeCoin', 'MEME', 1000000_u256, 1000000_u256, owner);

//     let dispatcher = IMemeCoinLaunchpadDispatcher { contract_address };

//     dispatcher.sell_tokens(0_u256); // Should panic
// }
