use starknet::{ContractAddress, get_caller_address};

/// Interface for ERC20 tokens (STRK)
#[starknet::interface]
trait IERC20<TContractState> {
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
}

#[derive(Drop, Serde, starknet::Store)]
pub struct MemeCoinData {
    pub address: ContractAddress,
    pub creator: ContractAddress,
    pub name: felt252,
    pub symbol: felt252,
    pub initial_supply: u256,
    pub description: felt252,
    pub ipfs_cid: ByteArray,
    pub social_links: felt252,
}

#[starknet::interface]
pub trait IMemeCoinFactory<TContractState> {
    fn create_memecoin(
        ref self: TContractState,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        initial_strk_deposit: u256,
        description: felt252,
        ipfs_cid: ByteArray,
        social_links: felt252,
    ) -> ContractAddress;

    fn get_created_memecoins(self: @TContractState) -> Array<MemeCoinData>;
    fn get_total_created(self: @TContractState) -> u256;
}

#[starknet::contract]
mod MemeCoinFactory {
    use starknet::get_contract_address;
use super::MemeCoinData;
    use starknet::storage::StoragePathEntry;
    use super::{IMemeCoinFactory, ContractAddress, get_caller_address};
    use starknet::syscalls::deploy_syscall;
    use starknet::class_hash::ClassHash;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::IERC20Dispatcher;
    use super::IERC20DispatcherTrait;

    #[storage]
    struct Storage {
        memecoin_class_hash: ClassHash,
        curve_factor: u256, // Hardcoded as STRK equivalent of 1ETH
        marketplace_fee_address: ContractAddress,
        created_memecoins: starknet::storage::Map<felt252, MemeCoinData>,
        total_created: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MemeCoinCreated: MemeCoinCreated,
    }

    #[derive(Drop, starknet::Event)]
    struct MemeCoinCreated {
        #[key]
        creator: ContractAddress,
        #[key]
        memecoin_address: ContractAddress,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        initial_strk_deposit: u256,
        description: felt252,
        social_links: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, memecoin_class_hash: ClassHash, marketplace_fee_address: ContractAddress) {
        self.memecoin_class_hash.write(memecoin_class_hash);
        self.marketplace_fee_address.write(marketplace_fee_address);
        // Hardcode curve factor as STRK equivalent of 1ETH (assuming 1 ETH = 10^18 wei, adjust as needed)
        self.curve_factor.write(1000000000000000000_u256); // 1e18
    }

    #[abi(embed_v0)]
    impl MemeCoinFactoryImpl of IMemeCoinFactory<ContractState> {
        fn create_memecoin(
            ref self: ContractState,
            name: felt252,
            symbol: felt252,
            initial_supply: u256,
            initial_strk_deposit: u256,
            description: felt252,
            ipfs_cid: ByteArray,
            social_links: felt252,
        ) -> ContractAddress {
            // Basic validation
            assert(name != 0, 'Name cannot be empty');
            assert(symbol != 0, 'Symbol cannot be empty');
            assert(initial_supply > 0_u256, 'Initial supply must be positive');

            // Scale deposit automatically (so user passes e.g. 10, not 10*1e18)
            let deposit_scaled = initial_strk_deposit * 1000000000000000000_u256;

            // Bounds checks to prevent overflow
            assert(initial_supply >= 10_u256, 'Supply too small'); // Min 10 tokens
            assert(initial_supply <= 980000000000000000_u256, 'Supply too large'); // Max ~10^18 tokens
            assert(deposit_scaled >= 1000000000000000000_u256, 'Deposit too small'); // Min 1 STRK
            assert(deposit_scaled <= 10000000000000000000000_u256, 'Deposit too large'); // Max 10^4 STRK

            let creator = get_caller_address();

            // Calculate 2% marketplace fee (avoid overflow by dividing first)
            let fee_amount = deposit_scaled / 100 * 2;
            let net_deposit = deposit_scaled - fee_amount;

            // Ensure net_deposit > 0 after fee deduction
            assert(net_deposit > 0, 'Deposit too small after fee');

            // Transfer full deposit to factory first
            let strk_address: ContractAddress = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap();
            let strk_dispatcher = IERC20Dispatcher { contract_address: strk_address };
            let factory_address = get_contract_address();

            // Check allowance to prevent underflow
            let current_allowance = strk_dispatcher.allowance(creator, factory_address);
            assert(current_allowance >= deposit_scaled, 'Insufficient STRK allowance');

            let deposit_success = strk_dispatcher.transfer_from(creator, factory_address, deposit_scaled);
            assert(deposit_success, 'Deposit transfer failed');

            // Transfer fee from factory to marketplace
            let fee_success = strk_dispatcher.transfer(self.marketplace_fee_address.read(), fee_amount);
            assert(fee_success, 'Fee transfer failed');

            let curve_factor = net_deposit / initial_supply / initial_supply;
            assert(curve_factor > 0, 'Curve factor must be positive');

            // Deploy the memecoin contract
            let mut constructor_calldata = ArrayTrait::new();
            constructor_calldata.append(name);
            constructor_calldata.append(symbol);
            constructor_calldata.append(initial_supply.low.into());
            constructor_calldata.append(initial_supply.high.into());
            constructor_calldata.append(curve_factor.low.into());
            constructor_calldata.append(curve_factor.high.into());
            constructor_calldata.append(net_deposit.low.into());
            constructor_calldata.append(net_deposit.high.into());
            constructor_calldata.append(creator.into());
            // STRK contract address (placeholder - should be passed from frontend)
            let strk_address: ContractAddress = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap();
            constructor_calldata.append(strk_address.into());
            constructor_calldata.append(self.marketplace_fee_address.read().into());

            let (memecoin_address, _) = deploy_syscall(
                self.memecoin_class_hash.read(),
                0, // salt
                constructor_calldata.span(),
                false
            ).unwrap();

            // Transfer net deposit to the memecoin contract
            let liquidity_success = strk_dispatcher.transfer(memecoin_address, net_deposit);
            assert(liquidity_success, 'Liquidity transfer failed');

            // Store the created memecoin data
            let current_index = self.total_created.read();
            let _index_felt: felt252 = current_index.low.into();
            let memecoin_data = MemeCoinData {
                address: memecoin_address,
                creator,
                name,
                symbol,
                initial_supply,
                description,
                ipfs_cid,
                social_links,
            };
            self.created_memecoins.entry(_index_felt).write(memecoin_data);
            self.total_created.write(current_index + 1_u256);

            // Emit event
            self.emit(MemeCoinCreated {
                creator,
                memecoin_address,
                name,
                symbol,
                initial_supply,
                initial_strk_deposit, // Keep original amount in event
                description,
                social_links,
            });

            memecoin_address
        }

        fn get_created_memecoins(self: @ContractState) -> Array<MemeCoinData> {
            let total = self.total_created.read();
            let mut result = ArrayTrait::new();
            let mut i: u256 = 0;
            while i < total {
                let _index_felt: felt252 = i.low.into();
                result.append(self.created_memecoins.entry(_index_felt).read());
                i += 1;
            };
            result
        }

        fn get_total_created(self: @ContractState) -> u256 {
            self.total_created.read()
        }
    }
}