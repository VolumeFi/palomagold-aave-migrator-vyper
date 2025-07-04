# PalomaGold AAVE Migrator Vyper

A Vyper smart contract that facilitates migration from AAVE aTokens to PalomaGold (PAGLD) tokens through a cross-chain bridge system.

## Overview

This contract enables users to:
1. Migrate AAVE aTokens to USDC and then to PalomaGold
2. Withdraw PAGLD tokens to the Paloma blockchain
3. Release USDC to recipients on the current blockchain

## Contract Architecture

### Key Components

- **AAVE Integration**: Withdraws underlying assets from AAVE Pool V3
- **Curve Swap Router**: Handles token swaps to USDC
- **Compass Bridge**: Facilitates cross-chain transfers to Paloma
- **Fee Management**: Collects gas fees and service fees
- **Nonce System**: Prevents replay attacks and tracks operations

### State Variables

```vyper
# Core addresses
compass: address                    # Cross-chain bridge contract
refund_wallet: address             # Wallet to receive gas fees
gas_fee: uint256                   # Gas fee amount in wei
service_fee_collector: address     # Address to receive service fees
service_fee: uint256               # Service fee percentage (basis points)
last_deposit_nonce: uint256        # Last migration nonce
last_withdraw_nonce: uint256       # Last withdrawal nonce
send_nonces: HashMap[uint256, bool] # Tracks used nonces
paloma: bytes32                    # Paloma blockchain identifier

# Immutable addresses
WETH: address                      # Wrapped ETH contract
Router: address                    # Curve swap router
Pool: address                      # AAVE Pool V3
USDC: address                      # USDC token
GoldWallet: address               # PalomaGold wallet
pagld: address                    # PAGLD token
```

## Function Documentation

### Constructor

#### `__init__(_compass, _weth, _router, _pool, _usdc, _pagld, _gold_wallet, _refund_wallet, _gas_fee, _service_fee_collector, _service_fee)`

**Purpose**: Initializes the contract with all required addresses and fee parameters.

**Parameters**:
- `_compass`: Cross-chain bridge contract address
- `_weth`: Wrapped ETH contract address
- `_router`: Curve swap router address
- `_pool`: AAVE Pool V3 address
- `_usdc`: USDC token address
- `_pagld`: PAGLD token address
- `_gold_wallet`: PalomaGold wallet address
- `_refund_wallet`: Gas fee collection wallet
- `_gas_fee`: Gas fee amount in wei
- `_service_fee_collector`: Service fee collection address
- `_service_fee`: Service fee percentage (must be < 10^18)

**Security Checks**:
- Validates service fee is less than denominator (100%)

**Events Emitted**:
- `UpdateCompass`
- `UpdateRefundWallet`
- `UpdateGasFee`
- `UpdateServiceFeeCollector`
- `UpdateServiceFee`

**Example Usage**:
```python
# Deploy with Ape
migrator = project.migrator.deploy(
    compass="0x3c1864a873879139C1BD87c7D95c4e475A91d19C",
    weth="0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
    router="0x2191718CD32d02B8E60BAdFFeA33E4B5DD9A0A0D",
    pool="0x794a61358D6845594F94dc1DB02A252b5b4814aD",
    usdc="0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
    pagld="0x3f146767AeC2F10484210a6525a807F8eA68613d",
    gold_wallet="0x22a017ec45ea1ae0b43b1aa55f50fffe1da468ec",
    refund_wallet="0x6dc0A87638CD75Cc700cCdB226c7ab6C054bc70b",
    gas_fee=3_000_000_000_000_000,  # 0.003 ETH
    service_fee_collector="0xe693603C9441f0e645Af6A5898b76a60dbf757F4",
    service_fee=2_500_000_000_000_000,  # 0.25%
    sender=deployer
)
```

### Core Migration Function

#### `migrate_atoken_to_palomagold(a_asset, swap_info)`

**Purpose**: Migrates AAVE aTokens to USDC and sends to PalomaGold wallet.

**Parameters**:
- `a_asset`: AAVE aToken address to migrate
- `swap_info`: SwapInfo struct containing route, parameters, and amounts

**Security Features**:
- `@nonreentrant`: Prevents reentrancy attacks
- `@payable`: Accepts ETH for gas fees
- Validates swap amounts and routes
- Collects gas and service fees

**Process Flow**:
1. Collects gas fee from msg.value
2. Transfers aToken from user to contract
3. Withdraws underlying asset from AAVE Pool
4. Swaps asset to USDC via Curve router (if route provided)
5. Deducts service fee
6. Transfers USDC to GoldWallet
7. Increments deposit nonce
8. Emits Migrated event

**Example Usage**:
```python
# Prepare swap info
swap_info = {
    "route": ["0x...", "0x...", ...],  # 11 addresses
    "swap_params": [[...], [...], ...], # 5x5 uint256 array
    "amount": 1000000000000000000,     # 1 token
    "expected": 950000000,             # Expected USDC amount
    "pools": ["0x...", "0x...", ...]   # 5 pool addresses
}

# Migrate aToken
migrator.migrate_atoken_to_palomagold(
    a_asset="0x...",  # aToken address
    swap_info=swap_info,
    value=gas_fee,    # Include gas fee
    sender=user
)
```

### Withdrawal Function

#### `withdraw(amount)`

**Purpose**: Sends PAGLD tokens to Paloma blockchain via Compass bridge.

**Parameters**:
- `amount`: Amount of PAGLD tokens to withdraw

**Security Features**:
- `@payable`: Accepts ETH for gas fees
- Validates token transfer
- Increments withdrawal nonce

**Process Flow**:
1. Collects gas fee from msg.value
2. Transfers PAGLD from user to contract
3. Sends tokens to Paloma via Compass bridge
4. Increments withdrawal nonce
5. Emits Withdrawn event

**Example Usage**:
```python
# Withdraw PAGLD to Paloma
migrator.withdraw(
    amount=1000000000000000000,  # 1 PAGLD
    value=gas_fee,               # Include gas fee
    sender=user
)
```

### Release Function

#### `release(recipient, amount, nonce)`

**Purpose**: Releases USDC to a recipient on the current blockchain.

**Parameters**:
- `recipient`: Address to receive USDC
- `amount`: Amount of USDC to release
- `nonce`: Unique nonce to prevent replay attacks

**Security Features**:
- Only callable by Compass contract
- Validates Paloma signature
- Prevents nonce reuse
- Tracks used nonces

**Process Flow**:
1. Validates caller is Compass contract
2. Validates Paloma signature
3. Checks nonce hasn't been used
4. Transfers USDC to recipient
5. Marks nonce as used
6. Emits Released event

**Example Usage**:
```python
# Called by Compass contract
migrator.release(
    recipient="0x...",
    amount=1000000,  # 1 USDC (6 decimals)
    nonce=123,
    sender=compass_contract
)
```

### Internal Helper Functions

#### `_safe_approve(_token, _to, _value)`

**Purpose**: Safely approves token spending with error handling.

**Security**: Uses `default_return_value=True` to handle non-standard ERC20 tokens.

#### `_safe_transfer(_token, _to, _value)`

**Purpose**: Safely transfers tokens with error handling.

**Security**: Reverts on failed transfers.

#### `_safe_transfer_from(_token, _from, _to, _value)`

**Purpose**: Safely transfers tokens from another address with error handling.

**Security**: Reverts on failed transfers.

#### `_paloma_check()`

**Purpose**: Validates that the caller is the Compass contract and has valid Paloma signature.

**Security**: 
- Checks msg.sender is compass address
- Validates Paloma signature in calldata

### View Functions

#### `usdc_balance() -> uint256`

**Purpose**: Returns the contract's USDC balance.

**Returns**: Current USDC balance of the contract.

### Administrative Functions

#### `update_compass(new_compass)`

**Purpose**: Updates the Compass bridge contract address.

**Security**:
- Only callable by current compass
- SLC must be unavailable

#### `set_paloma()`

**Purpose**: Sets the Paloma blockchain identifier.

**Security**:
- Only callable by compass
- Can only be set once
- Validates calldata length

#### `update_refund_wallet(new_refund_wallet)`

**Purpose**: Updates the gas fee refund wallet address.

**Security**: Requires Paloma signature validation.

#### `update_gas_fee(new_gas_fee)`

**Purpose**: Updates the gas fee amount.

**Security**: Requires Paloma signature validation.

#### `update_service_fee_collector(new_service_fee_collector)`

**Purpose**: Updates the service fee collector address.

**Security**: Requires Paloma signature validation.

#### `update_service_fee(new_service_fee)`

**Purpose**: Updates the service fee percentage.

**Security**: 
- Requires Paloma signature validation
- Validates fee is less than denominator

## Events

### Core Events
- `Migrated(sender, usdc_amount, nonce)`: Emitted when migration completes
- `Withdrawn(sender, pagld_amount, nonce)`: Emitted when withdrawal is processed
- `Released(recipient, amount, nonce)`: Emitted when USDC is released

### Administrative Events
- `UpdateCompass(old_compass, new_compass)`: Compass address updates
- `UpdateRefundWallet(old_refund_wallet, new_refund_wallet)`: Refund wallet updates
- `SetPaloma(paloma)`: Paloma identifier setting
- `UpdateGasFee(old_gas_fee, new_gas_fee)`: Gas fee updates
- `UpdateServiceFeeCollector(old_collector, new_collector)`: Fee collector updates
- `UpdateServiceFee(old_fee, new_fee)`: Service fee updates

## Security Considerations

### Reentrancy Protection
- `migrate_atoken_to_palomagold` uses `@nonreentrant` decorator
- External calls are made after state changes

### Access Control
- Administrative functions require Paloma signature validation
- Compass contract is the only authorized caller for certain functions

### Nonce System
- Prevents replay attacks on release function
- Tracks both deposit and withdrawal nonces separately

### Fee Management
- Gas fees are collected upfront and sent to refund wallet
- Service fees are calculated and deducted from swap proceeds
- All fee parameters are configurable with proper validation

### Token Safety
- Uses safe transfer functions with error handling
- Supports non-standard ERC20 tokens via `default_return_value=True`

## Testing

### Prerequisites
- Python 3.8+
- Ape Framework
- Access to Arbitrum network

### Running Tests

Currently, this project does not include automated tests. To add tests:

1. Create a `tests/` directory
2. Add test files with `test_` prefix
3. Use Ape's testing framework

Example test structure:
```
tests/
├── test_migration.py
├── test_withdrawal.py
├── test_admin_functions.py
└── conftest.py
```

### Manual Testing

To test the contract manually:

1. Deploy to testnet:
```bash
ape run scripts/deploy_arb.py --network arbitrum:sepolia
```

2. Test migration flow:
```python
# Approve aToken spending
atoken.approve(migrator.address, amount, sender=user)

# Migrate aToken
migrator.migrate_atoken_to_palomagold(
    a_asset=atoken.address,
    swap_info=swap_info,
    value=gas_fee,
    sender=user
)
```

3. Test withdrawal flow:
```python
# Approve PAGLD spending
pagld.approve(migrator.address, amount, sender=user)

# Withdraw to Paloma
migrator.withdraw(amount, value=gas_fee, sender=user)
```

## Deployment

### Arbitrum Mainnet Deployment

The contract is deployed on Arbitrum mainnet at:
`0x86B4260727FF6F50a21660B7A09B7905022c8675`

### Deployment Parameters

```python
compass = "0x3c1864a873879139C1BD87c7D95c4e475A91d19C"
weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"
router = "0x2191718CD32d02B8E60BAdFFeA33E4B5DD9A0A0D"
pool = "0x794a61358D6845594F94dc1DB02A252b5b4814aD"
usdc = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
pagld = "0x3f146767AeC2F10484210a6525a807F8eA68613d"
gold_wallet = "0x22a017ec45ea1ae0b43b1aa55f50fffe1da468ec"
refund_wallet = "0x6dc0A87638CD75Cc700cCdB226c7ab6C054bc70b"
gas_fee = 3_000_000_000_000_000  # 0.003 ETH
service_fee_collector = "0xe693603C9441f0e645Af6A5898b76a60dbf757F4"
service_fee = 2_500_000_000_000_000  # 0.25%
```

## License

Apache 2.0

## Author

Volume.finance 