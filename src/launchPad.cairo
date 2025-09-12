use starknet::ContractAddress;

/// Interface for MemeCoinLaunchpad
#[starknet::interface]
pub trait IMemeCoinLaunchpad<TContractState> {
    fn buy_tokens(ref self: TContractState, amount_in: u256);
    fn sell_tokens(ref self: TContractState, tokens_in: u256);
    fn get_current_price(self: @TContractState) -> u256;
    fn get_holder_count(self: @TContractState) -> u256;
    fn get_buyer_count(self: @TContractState) -> u256;
    fn get_seller_count(self: @TContractState) -> u256;
    fn is_holder(self: @TContractState, address: ContractAddress) -> bool;
    fn is_buyer(self: @TContractState, address: ContractAddress) -> bool;
    fn is_seller(self: @TContractState, address: ContractAddress) -> bool;
}

#[starknet::contract]
mod MemeCoinLaunchpad {
    use super::IMemeCoinLaunchpad;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess, StorageMapWriteAccess};

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    const DECIMALS: u256 = 1000000000000000000; // 10^18

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        curve_factor: u256, // Bonding curve multiplier (e.g., 1e12 for precision)
        total_supply: u256, // Tracks minted supply for curve
        liquidity_pool: u256, // ETH/STARK equivalent collected
        holders: Map<ContractAddress, bool>, // Tracks unique holders
        buyers: Map<ContractAddress, bool>, // Tracks unique buyers
        sellers: Map<ContractAddress, bool>, // Tracks unique sellers
        holder_count: u256,
        buyer_count: u256,
        seller_count: u256,
        strk_contract: ContractAddress, // STRK token contract address
        marketplace_fee_address: ContractAddress, // Address to receive marketplace fees
    }

    fn felt252_to_byte_array(value: felt252) -> ByteArray {
        let mut bytes = ArrayTrait::new();
        let mut temp: u256 = value.into();
        let mut i: u32 = 0;
        while i < 32_u32 {
            let byte: u8 = (temp % 256).try_into().unwrap();
            if byte != 0 || bytes.len() > 0 {
                bytes.append(byte);
            }
            temp = temp / 256;
            i += 1_u32;
        };

        if bytes.len() == 0 {
            return "0";
        }

        // Reverse the bytes to correct endianness for string representation
        let mut result = "";
        let mut j = bytes.len();
        while j > 0 {
            j -= 1;
            result.append_byte(*bytes.at(j));
        };

        result
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        TokensBought: TokensBought,
        TokensSold: TokensSold,
    }

    #[derive(Drop, starknet::Event)]
    struct TokensBought {
        buyer: ContractAddress,
        amount_in: u256,
        fee_amount: u256,
        tokens_out: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TokensSold {
        seller: ContractAddress,
        tokens_in: u256,
        fee_amount: u256,
        amount_out: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        curve_factor: u256,
        initial_deposit: u256,
        owner: ContractAddress,
        strk_contract: ContractAddress,
        marketplace_fee_address: ContractAddress,
    ) {
        // Convert felt252 to ByteArray properly (avoiding format! issues)
        let name_bytes = felt252_to_byte_array(name);
        let symbol_bytes = felt252_to_byte_array(symbol);

        // Initialize ERC20 with ByteArray instead of format!
        self.erc20.initializer(name_bytes, symbol_bytes);
        self.ownable.initializer(owner);
        self.curve_factor.write(curve_factor);
        self.total_supply.write(initial_supply * DECIMALS);
        self.liquidity_pool.write(initial_deposit);
        self.strk_contract.write(strk_contract);
        self.marketplace_fee_address.write(marketplace_fee_address);
        self.erc20.mint(owner, initial_supply * DECIMALS); // Mint initial to owner or liquidity

        // Initialize tracking
        if initial_supply > 0 {
            self.holders.write(owner, true);
            self.holder_count.write(1);
        }
        self.buyer_count.write(0);
        self.seller_count.write(0);
    }

    #[abi(embed_v0)]
    impl MemeCoinLaunchpadExternalImpl of IMemeCoinLaunchpad<ContractState> {
        fn buy_tokens(ref self: ContractState, amount_in: u256) {
            assert(amount_in > 0, 'Amount must be positive');
            let caller = get_caller_address();
            let contract_address = get_contract_address();

            // Scale amount_in to wei units
            let scaled_in = amount_in * DECIMALS;

            // Calculate 2% marketplace fee
            let fee_amount = scaled_in * 2 / 100;
            assert(scaled_in >= fee_amount, 'Fee exceeds deposit');
            let net_amount = scaled_in - fee_amount;

            // Transfer STRK from caller to contract
            let strk_dispatcher = IERC20Dispatcher { contract_address: self.strk_contract.read() };

            // Check allowance only (balance check removed - transfer_from handles it)
            let allowance = strk_dispatcher.allowance(caller, contract_address);
            assert(allowance >= scaled_in, 'Insufficient STRK allowance');

            let transfer_success = strk_dispatcher.transfer_from(caller, contract_address, scaled_in);
            assert(transfer_success, 'STRK transfer failed');

            // Transfer fee to marketplace
            let fee_success = strk_dispatcher.transfer(self.marketplace_fee_address.read(), fee_amount);
            assert(fee_success, 'Fee transfer failed');

            let price = self.get_current_price();
            let tokens_out = (net_amount / price) * DECIMALS;
            assert(tokens_out > 0, 'Insufficient output');

            self.erc20.mint(caller, tokens_out);
            self.total_supply.write(self.total_supply.read() + tokens_out);
            self.liquidity_pool.write(self.liquidity_pool.read() + net_amount);

            // Track buyers
            if !self.buyers.read(caller) {
                self.buyers.write(caller, true);
                self.buyer_count.write(self.buyer_count.read() + 1);
            }

            // Track holders
            if !self.holders.read(caller) {
                self.holders.write(caller, true);
                self.holder_count.write(self.holder_count.read() + 1);
            }

            self.emit(TokensBought { buyer: caller, amount_in, fee_amount, tokens_out });
        }

        fn sell_tokens(ref self: ContractState, tokens_in: u256) {
            assert(tokens_in > 0, 'Tokens must be positive');
            assert(tokens_in >= 1, 'Minimum sell 1 token');
            let caller = get_caller_address();
            let contract_address = get_contract_address();
            let price = self.get_current_price();

            // Scale tokens_in to wei internally
            let scaled_tokens_in = tokens_in * DECIMALS;
            assert(scaled_tokens_in <= self.total_supply.read(), 'Total supply exceeded');

            if tokens_in != 0 {
                let max_price = u256 { low: 0xFFFFFFFF, high: 0xFFFFFFFF } / tokens_in; // Approximate max
                assert(price <= max_price, 'Price overflow');
            }

            let gross_amount = tokens_in * price;
            assert(gross_amount > 0, 'Insufficient output');
            assert(gross_amount <= self.liquidity_pool.read(), 'Insufficient liquidity');

            // Calculate 2% marketplace fee
            let fee_amount = gross_amount * 2 / 100;
            let net_amount = gross_amount - fee_amount;

            // Check allowance and transfer meme tokens to contract before burning
            let allowance = self.erc20.allowance(caller, contract_address);
            assert(allowance >= scaled_tokens_in, 'Insufficient allowance');

            let transfer_success = self.erc20.transfer_from(caller, contract_address, scaled_tokens_in);
            assert(transfer_success, 'Meme token transfer failed');

            self.erc20.burn(contract_address, scaled_tokens_in);
            self.total_supply.write(self.total_supply.read() - scaled_tokens_in);
            self.liquidity_pool.write(self.liquidity_pool.read() - gross_amount);

            // Transfer STRK to seller
            let strk_dispatcher = IERC20Dispatcher { contract_address: self.strk_contract.read() };
            let transfer_success = strk_dispatcher.transfer(caller, net_amount);
            assert(transfer_success, 'STRK transfer to seller failed');

            // Transfer fee to marketplace
            let fee_success = strk_dispatcher.transfer(self.marketplace_fee_address.read(), fee_amount);
            assert(fee_success, 'Fee transfer failed');

            // Track sellers
            if !self.sellers.read(caller) {
                self.sellers.write(caller, true);
                self.seller_count.write(self.seller_count.read() + 1);
            }

            // Check if balance becomes 0, remove from holders
            let balance = self.erc20.balance_of(caller);
            if balance == 0 && self.holders.read(caller) {
                self.holders.write(caller, false);
                self.holder_count.write(self.holder_count.read() - 1);
            }

            self.emit(TokensSold { seller: caller, tokens_in, fee_amount, amount_out: net_amount });
        }

        fn get_current_price(self: @ContractState) -> u256 {
            // ADD SAFE MULTIPLICATION FOR PRICE CALCULATION
            let total_supply_tokens = self.total_supply.read() / DECIMALS;
            let curve_factor = self.curve_factor.read();

            // Prevent overflow in price calculation
            if total_supply_tokens != 0 {
                let max_curve = u256 { low: 0xFFFFFFFF, high: 0xFFFFFFFF } / total_supply_tokens;
                assert(curve_factor <= max_curve, 'Curve overflow');
            }

            total_supply_tokens * curve_factor
        }

        fn get_holder_count(self: @ContractState) -> u256 {
            self.holder_count.read()
        }

        fn get_buyer_count(self: @ContractState) -> u256 {
            self.buyer_count.read()
        }

        fn get_seller_count(self: @ContractState) -> u256 {
            self.seller_count.read()
        }

        fn is_holder(self: @ContractState, address: ContractAddress) -> bool {
            self.holders.read(address)
        }

        fn is_buyer(self: @ContractState, address: ContractAddress) -> bool {
            self.buyers.read(address)
        }

        fn is_seller(self: @ContractState, address: ContractAddress) -> bool {
            self.sellers.read(address)
        }
    }
}