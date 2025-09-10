use starknet::ContractAddress;

#[derive(Drop, Serde)]
pub struct MemeCoin {
    pub address: ContractAddress,
    pub name: felt252,
    pub symbol: felt252,
    pub description: felt252,
    pub ipfs_cid: ByteArray,
    pub social_links: felt252,
    pub creator: ContractAddress,
    pub initial_supply: u256,
    pub created_at: u64,
}