use starknet::{ContractAddress, get_caller_address};

#[starknet::interface]
pub trait IMemeCoinFactory<TContractState> {
    fn create_memecoin(
        ref self: TContractState,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        initial_strk_deposit: u256,
        description: felt252,
        ipfs_cid: felt252,
        social_links: felt252,
    ) -> ContractAddress;
}

#[starknet::contract]
mod MemeCoinFactory {
    use super::{IMemeCoinFactory, ContractAddress, get_caller_address};
    use starknet::syscalls::deploy_syscall;
    use starknet::class_hash::ClassHash;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        memecoin_class_hash: ClassHash,
        curve_factor: u256, // Hardcoded as STRK equivalent of 1ETH
        marketplace_fee_address: ContractAddress,
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
        description: felt252,
        ipfs_cid: felt252,
        social_links: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, memecoin_class_hash: ClassHash, marketplace_fee_address: ContractAddress) {
        self.memecoin_class_hash.write(memecoin_class_hash);
        self.marketplace_fee_address.write(marketplace_fee_address);
        // Hardcode curve factor as STRK equivalent of 1ETH (assuming 1 ETH = 10^18 wei, adjust as needed)
        self.curve_factor.write(1000000000000000000); // 1e18
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
            ipfs_cid: felt252,
            social_links: felt252,
        ) -> ContractAddress {
            // Basic validation
            assert(name != 0, 'Name cannot be empty');
            assert(symbol != 0, 'Symbol cannot be empty');
            assert(initial_supply > 0, 'Initial supply must be positive');

            let creator = get_caller_address();
            let curve_factor = self.curve_factor.read();

            // Deploy the memecoin contract
            let mut constructor_calldata = ArrayTrait::new();
            constructor_calldata.append(name);
            constructor_calldata.append(symbol);
            constructor_calldata.append(initial_supply.low.into());
            constructor_calldata.append(initial_supply.high.into());
            constructor_calldata.append(curve_factor.low.into());
            constructor_calldata.append(curve_factor.high.into());
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

            // Emit event
            self.emit(MemeCoinCreated {
                creator,
                memecoin_address,
                name,
                symbol,
                initial_supply,
                description,
                ipfs_cid,
                social_links,
            });

            memecoin_address
        }
    }
}