#pragma version 0.4.0
#pragma optimize gas
#pragma evm-version cancun
"""
@title PalomaGold AAVE Migrator Vyper
@license Apache 2.0
@author Volume.finance
"""

struct SwapInfo:
    route: address[11]
    swap_params: uint256[5][5]
    amount: uint256
    expected: uint256
    pools: address[5]

interface ERC20:
    def balanceOf(_owner: address) -> uint256: view
    def approve(_spender: address, _value: uint256) -> bool: nonpayable
    def transfer(_to: address, _value: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable

interface AToken:
    def UNDERLYING_ASSET_ADDRESS() -> address: view

interface Weth:
    def withdraw(amount: uint256): nonpayable

interface CurveSwapRouter:
    def exchange(
        _route: address[11],
        _swap_params: uint256[5][5],
        _amount: uint256,
        _expected: uint256,
        _pools: address[5]=empty(address[5]),
        _receiver: address=msg.sender
    ) -> uint256: payable

interface AAVEPoolV3:
    def withdraw(asset: address, amount: uint256, to: address) -> uint256: nonpayable

interface Compass:
    def send_token_to_paloma(token: address, receiver: bytes32, amount: uint256): nonpayable
    def slc_switch() -> bool: view

DENOMINATOR: constant(uint256) = 10 ** 18
VETH: constant(address) = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
WETH: public(immutable(address))
Router: public(immutable(address))
Pool: public(immutable(address))
USDC: public(immutable(address))
GoldWallet: public(immutable(address))
pagld: public(immutable(address))

compass: public(address)
refund_wallet: public(address)
gas_fee: public(uint256)
service_fee_collector: public(address)
service_fee: public(uint256)
last_deposit_nonce: public(uint256)
last_withdraw_nonce: public(uint256)
send_nonces: public(HashMap[uint256, bool])
paloma: public(bytes32)

event Migrated:
    sender: address
    usdc_amount: uint256
    nonce: uint256

event Withdrawn:
    sender: address
    pagld_amount: uint256
    nonce: uint256

event Released:
    recipient: address
    amount: uint256
    nonce: uint256

event UpdateCompass:
    old_compass: address
    new_compass: address

event UpdateRefundWallet:
    old_refund_wallet: address
    new_refund_wallet: address

event SetPaloma:
    paloma: bytes32

event UpdateGasFee:
    old_gas_fee: uint256
    new_gas_fee: uint256

event UpdateServiceFeeCollector:
    old_service_fee_collector: address
    new_service_fee_collector: address

event UpdateServiceFee:
    old_service_fee: uint256
    new_service_fee: uint256

@deploy
def __init__(_compass: address, _weth: address, _router: address, _pool: address, _usdc: address, _pagld: address, _gold_wallet: address, _refund_wallet: address, _gas_fee: uint256, _service_fee_collector: address, _service_fee: uint256):
    self.compass = _compass
    self.refund_wallet = _refund_wallet
    self.gas_fee = _gas_fee
    self.service_fee_collector = _service_fee_collector
    assert _service_fee < DENOMINATOR, "Invalid service fee"
    self.service_fee = _service_fee
    Router = _router
    WETH = _weth
    Pool = _pool
    USDC = _usdc
    GoldWallet = _gold_wallet
    pagld = _pagld
    log UpdateCompass(empty(address), _compass)
    log UpdateRefundWallet(empty(address), _refund_wallet)
    log UpdateGasFee(0, _gas_fee)
    log UpdateServiceFeeCollector(empty(address), _service_fee_collector)
    log UpdateServiceFee(0, _service_fee)

@internal
def _safe_approve(_token: address, _to: address, _value: uint256):
    assert extcall ERC20(_token).approve(_to, _value, default_return_value=True), "Failed approve"

@internal
def _safe_transfer(_token: address, _to: address, _value: uint256):
    assert extcall ERC20(_token).transfer(_to, _value, default_return_value=True), "Failed transfer"

@internal
def _safe_transfer_from(_token: address, _from: address, _to: address, _value: uint256):
    assert extcall ERC20(_token).transferFrom(_from, _to, _value, default_return_value=True), "Failed transferFrom"

@external
@view
def usdc_balance() -> uint256:
    return staticcall ERC20(USDC).balanceOf(self)

@external
@payable
@nonreentrant
def migrate_atoken_to_palomagold(a_asset: address, swap_info: SwapInfo):
    _value: uint256 = msg.value
    _gas_fee: uint256 = self.gas_fee
    if _gas_fee > 0:
        _value -= _gas_fee
        send(self.refund_wallet, _gas_fee)
    if _value > 0:
        send(msg.sender, _value)
    _amount: uint256 = swap_info.amount
    self._safe_transfer_from(a_asset, msg.sender, self, _amount)
    _asset: address = staticcall AToken(a_asset).UNDERLYING_ASSET_ADDRESS()

    extcall AAVEPoolV3(Pool).withdraw(_asset, _amount, self)

    if swap_info.route[1] != empty(address):
        asset: address = swap_info.route[0]
        if asset != VETH:
            self._safe_approve(asset, Router, swap_info.amount)
            _value = 0
        else:
            extcall Weth(WETH).withdraw(swap_info.amount)
            _value = swap_info.amount
        
        _amount = staticcall ERC20(USDC).balanceOf(self)

        extcall CurveSwapRouter(Router).exchange(swap_info.route, swap_info.swap_params, swap_info.amount, swap_info.expected, swap_info.pools, value=_value)

        _amount = staticcall ERC20(USDC).balanceOf(self) - _amount
    
    assert _amount > 0, "Invalid amount"

    _service_fee: uint256 = self.service_fee
    if _service_fee > 0:
        _service_fee_collector: address = self.service_fee_collector
        _service_fee_amount: uint256 = _amount * _service_fee // DENOMINATOR
        self._safe_transfer(USDC, _service_fee_collector, _service_fee_amount)
        _amount -= _service_fee_amount

    self._safe_transfer(USDC, GoldWallet, _amount)
    nonce: uint256 = self.last_deposit_nonce
    self.last_deposit_nonce = nonce + 1
    log Migrated(msg.sender, _amount, nonce)

@external
@payable
def withdraw(amount: uint256):
    _gas_fee: uint256 = self.gas_fee
    _value: uint256 = msg.value
    if _gas_fee > 0:
        _value -= _gas_fee
        send(self.refund_wallet, _gas_fee)
    if _value > 0:
        send(msg.sender, _value)
    self._safe_transfer_from(pagld, msg.sender, self, amount)
    extcall Compass(self.compass).send_token_to_paloma(pagld, self.paloma, amount)
    nonce: uint256 = self.last_withdraw_nonce
    self.last_withdraw_nonce = nonce + 1
    log Withdrawn(msg.sender, amount, nonce)

@external
def release(recipient: address, amount: uint256, nonce: uint256):
    self._paloma_check()
    assert not self.send_nonces[nonce], "Invalid nonce"
    self._safe_transfer(USDC, recipient, amount)
    self.send_nonces[nonce] = True
    log Released(recipient, amount, nonce)

@internal
def _paloma_check():
    assert msg.sender == self.compass, "Not compass"
    assert self.paloma == convert(slice(msg.data, unsafe_sub(len(msg.data), 32), 32), bytes32), "Invalid paloma"

@external
def update_compass(new_compass: address):
    _compass: address = self.compass
    assert msg.sender == _compass, "Not compass"
    assert not staticcall Compass(_compass).slc_switch(), "SLC is unavailable"
    self.compass = new_compass
    log UpdateCompass(msg.sender, new_compass)

@external
def set_paloma():
    assert msg.sender == self.compass and self.paloma == empty(bytes32) and len(msg.data) == 36, "Invalid"
    _paloma: bytes32 = convert(slice(msg.data, 4, 32), bytes32)
    self.paloma = _paloma
    log SetPaloma(_paloma)

@external
def update_refund_wallet(new_refund_wallet: address):
    self._paloma_check()
    old_refund_wallet: address = self.refund_wallet
    self.refund_wallet = new_refund_wallet
    log UpdateRefundWallet(old_refund_wallet, new_refund_wallet)

@external
def update_gas_fee(new_gas_fee: uint256):
    self._paloma_check()
    old_gas_fee: uint256 = self.gas_fee
    self.gas_fee = new_gas_fee
    log UpdateGasFee(old_gas_fee, new_gas_fee)

@external
def update_service_fee_collector(new_service_fee_collector: address):
    self._paloma_check()
    old_service_fee_collector: address = self.service_fee_collector
    self.service_fee_collector = new_service_fee_collector
    log UpdateServiceFeeCollector(old_service_fee_collector, new_service_fee_collector)

@external
def update_service_fee(new_service_fee: uint256):
    self._paloma_check()
    assert new_service_fee < DENOMINATOR, "Invalid service fee"
    old_service_fee: uint256 = self.service_fee
    self.service_fee = new_service_fee
    log UpdateServiceFee(old_service_fee, new_service_fee)

@external
@payable
def __default__():
    pass