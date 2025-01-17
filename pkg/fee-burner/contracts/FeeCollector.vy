# pragma version 0.3.10
"""
@title FeeCollector
@license MIT
@author Curve Finance
@notice Collects fees and delegates to burner for exchange
"""


interface ERC20:
    def approve(_to: address, _value: uint256) -> bool: nonpayable
    def transfer(_to: address, _value: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable
    def balanceOf(_owner: address) -> uint256: view

interface wETH:
    def balanceOf(_owner: address) -> uint256: view
    def transferFrom(_sender: address, _receiver: address, _amount: uint256): nonpayable
    def transfer(_receiver: address, _amount: uint256): nonpayable
    def withdraw(_amount: uint256): nonpayable
    def deposit(): payable

interface Curve:
    def withdraw_admin_fees(): nonpayable

interface Burner:
    def burn(_coins: DynArray[ERC20, MAX_LEN], _receiver: address): nonpayable
    def push_target() -> uint256: nonpayable
    def supportsInterface(_interface_id: bytes4) -> bool: view

interface Hooker:
    def duty_act(_hook_inputs: DynArray[HookInput, MAX_HOOK_LEN], _receiver: address=msg.sender) -> uint256: payable
    def buffer_amount() -> uint256: view
    def supportsInterface(_interface_id: bytes4) -> bool: view


event SetMaxFee:
    epoch: indexed(Epoch)
    max_fee: uint256

event SetBurner:
    burner: indexed(Burner)

event SetHooker:
    hooker: indexed(Hooker)

event SetTarget:
    target: indexed(ERC20)

event SetKilled:
    coin: indexed(ERC20)
    epoch_mask: Epoch

event SetOwner:
    owner: indexed(address)

event SetEmergencyOwner:
    emergency_owner: indexed(address)


enum Epoch:
    SLEEP  # 1
    COLLECT  # 2
    EXCHANGE  # 4
    FORWARD  # 8


struct Transfer:
    coin: ERC20
    to: address
    amount: uint256  # 2^256-1 for the whole balance


struct HookInput:
    hook_id: uint8
    value: uint256
    data: Bytes[8192]


struct RecoverInput:
    coin: ERC20
    amount: uint256


struct KilledInput:
    coin: ERC20
    killed: Epoch  # True where killed


ETH_ADDRESS: constant(address) = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
WETH: immutable(wETH)

MAX_LEN: constant(uint256) = 64
MAX_HOOK_LEN: constant(uint256) = 32
ONE: constant(uint256) = 10 ** 18  # Precision

START_TIME: constant(uint256) = 1600300800  # ts of distribution start
WEEK: constant(uint256) = 7 * 24 * 3600
EPOCH_TIMESTAMPS: constant(uint256[17]) = [
    0, 0,  # 1
    4 * 24 * 3600,  # 2
    0, 5 * 24 * 3600,   # 4
    0, 0, 0, 6 * 24 * 3600,  # 8
    0, 0, 0, 0, 0, 0, 0, WEEK,  # 16, next period
]

target: public(ERC20)  # coin swapped into
max_fee: public(uint256[9])  # max_fee[Epoch]

BURNER_INTERFACE_ID: constant(bytes4) = 0xa3b5e311
HOOKER_INTERFACE_ID: constant(bytes4) = 0xe569b44d
burner: public(Burner)
hooker: public(Hooker)

last_hooker_approve: uint256

is_killed: public(HashMap[ERC20, Epoch])
ALL_COINS: constant(ERC20) = empty(ERC20)  # Auxiliary indicator for all coins (=ZERO_ADDRESS)

owner: public(address)
emergency_owner: public(address)


@external
def __init__(_target_coin: ERC20, _weth: wETH, _owner: address, _emergency_owner: address):
    """
    @notice Contract constructor
    @param _target_coin Coin to swap to
    @param _weth Wrapped ETH(native coin) address
    @param _owner Owner address
    @param _emergency_owner Emergency owner address. Can kill the contract
    """
    self.target = _target_coin
    WETH = _weth
    self.owner = _owner
    self.emergency_owner = _emergency_owner

    self.max_fee[convert(Epoch.COLLECT, uint256)] = ONE / 100  # 1%
    self.max_fee[convert(Epoch.FORWARD, uint256)] = ONE / 100  # 1%

    self.is_killed[ALL_COINS] = Epoch.COLLECT | Epoch.FORWARD  # Set burner first
    self.is_killed[_target_coin] = Epoch.COLLECT | Epoch.EXCHANGE  # Keep target coin in contract

    log SetTarget(_target_coin)
    log SetOwner(_owner)
    log SetEmergencyOwner(_emergency_owner)
    log SetMaxFee(Epoch.COLLECT, ONE / 100)
    log SetMaxFee(Epoch.FORWARD, ONE / 100)
    log SetKilled(ALL_COINS, Epoch.COLLECT | Epoch.FORWARD)
    log SetKilled(_target_coin, Epoch.COLLECT | Epoch.FORWARD)


@external
@payable
def __default__():
    # Deposited ETH can be converted using `burn(ETH_ADDRESS)`
    pass


@external
def withdraw_many(_pools: DynArray[address, MAX_LEN]):
    """
    @notice Withdraw admin fees from multiple pools
    @param _pools List of pool address to withdraw admin fees from
    """
    for pool in _pools:
        Curve(pool).withdraw_admin_fees()


@external
@payable
def burn(_coin: address) -> bool:
    """
    @notice Transfer coin from contract with approval
    @dev Needed for back compatability along with dealing raw ETH
    @param _coin Coin to transfer
    @return True if did not fail, back compatability
    """
    if _coin == ETH_ADDRESS:  # Deposit
        WETH.deposit(value=self.balance)
    else:
        amount: uint256 = ERC20(_coin).balanceOf(msg.sender)
        assert ERC20(_coin).transferFrom(msg.sender, self, amount, default_return_value=True)
    return True


@internal
@pure
def _epoch_ts(ts: uint256) -> Epoch:
    ts = (ts - START_TIME) % WEEK
    for epoch in [Epoch.SLEEP, Epoch.COLLECT, Epoch.EXCHANGE, Epoch.FORWARD]:
        if ts < EPOCH_TIMESTAMPS[2 * convert(epoch, uint256)]:
            return epoch
    raise UNREACHABLE


@external
@view
def epoch(ts: uint256=block.timestamp) -> Epoch:
    """
    @notice Get epoch at certain timestamp
    @param ts Timestamp. Current by default
    @return Epoch
    """
    return self._epoch_ts(ts)


@internal
@pure
def _epoch_time_frame(epoch: Epoch, ts: uint256) -> (uint256, uint256):
    subset: uint256 = convert(epoch, uint256)
    assert subset & (subset - 1) == 0, "Bad Epoch"

    ts = ts - (ts - START_TIME) % WEEK
    return (ts + EPOCH_TIMESTAMPS[convert(epoch, uint256)], ts + EPOCH_TIMESTAMPS[2 * convert(epoch, uint256)])


@external
@view
def epoch_time_frame(_epoch: Epoch, _ts: uint256=block.timestamp) -> (uint256, uint256):
    """
    @notice Get time frame of certain epoch
    @param _epoch Epoch
    @param _ts Timestamp to anchor to. Current by default
    @return [start, end) time frame boundaries
    """
    return self._epoch_time_frame(_epoch, _ts)


@internal
@view
def _fee(epoch: Epoch, ts: uint256) -> uint256:
    start: uint256 = 0
    end: uint256 = 0
    start, end = self._epoch_time_frame(epoch, ts)
    if ts >= end:
        return 0
    return self.max_fee[convert(epoch, uint256)] * (ts + 1 - start) / (end - start)


@external
@view
def fee(_epoch: Epoch=empty(Epoch), _ts: uint256=block.timestamp) -> uint256:
    """
    @notice Calculate keeper's fee
    @param _epoch Epoch to count fee for
    @param _ts Timestamp of collection
    @return Fee with base 10^18
    """
    if _epoch == empty(Epoch):
        return self._fee(self._epoch_ts(_ts), _ts)
    return self._fee(_epoch, _ts)


@external
@nonreentrant("transfer")
def transfer(_transfers: DynArray[Transfer, MAX_LEN]):
    """
    @dev No approvals so can change burner easily
    @param _transfers Transfers to apply
    """
    assert msg.sender == self.burner.address, "Only Burner"
    epoch: Epoch = self._epoch_ts(block.timestamp)
    assert epoch in Epoch.COLLECT | Epoch.EXCHANGE, "Wrong Epoch"
    assert not self.is_killed[ALL_COINS] in epoch, "Killed epoch"

    for transfer in _transfers:
        assert not self.is_killed[transfer.coin] in epoch, "Killed coin"

        amount: uint256 = transfer.amount
        if amount == max_value(uint256):
            amount = transfer.coin.balanceOf(self)
        assert transfer.coin.transfer(transfer.to, amount, default_return_value=True)


@external
@nonreentrant("collect")
def collect(_coins: DynArray[ERC20, MAX_LEN], _receiver: address=msg.sender):
    """
    @notice Collect earned fees. Collection should happen under callback to earn caller fees.
    @param _coins Coins to collect sorted in ascending order
    @param _receiver Receiver of caller `collect_fee`s
    """
    assert self._epoch_ts(block.timestamp) == Epoch.COLLECT, "Wrong epoch"
    assert not self.is_killed[ALL_COINS] in Epoch.COLLECT, "Killed epoch"

    for i in range(len(_coins), bound=MAX_LEN):
        assert not self.is_killed[_coins[i]] in Epoch.COLLECT, "Killed coin"
        # Eliminate case of repeated coins
        if i > 0:
            assert convert(_coins[i].address, uint160) > convert(_coins[i - 1].address, uint160), "Coins not sorted"

    self.burner.burn(_coins, _receiver)


@external
@view
def can_exchange(_coins: DynArray[ERC20, MAX_LEN]) -> bool:
    """
    @notice Check whether coins are allowed to be exchanged
    @param _coins Coins to exchange
    @return Boolean value if coins are allowed to be exchanged
    """
    if self._epoch_ts(block.timestamp) != Epoch.EXCHANGE or\
        self.is_killed[ALL_COINS] in Epoch.EXCHANGE:
        return False
    for coin in _coins:
        if self.is_killed[coin] in Epoch.EXCHANGE:
            return False
    return True


@external
@payable
@nonreentrant("forward")
def forward(_hook_inputs: DynArray[HookInput, MAX_HOOK_LEN], _receiver: address=msg.sender) -> uint256:
    """
    @notice Transfer target coin forward
    @param _hook_inputs Input parameters for forward hooks
    @param _receiver Receiver of caller `forward_fee`
    @return Amount of received fee
    """
    assert self._epoch_ts(block.timestamp) == Epoch.FORWARD, "Wrong epoch"
    target: ERC20 = self.target
    assert not (self.is_killed[ALL_COINS] | self.is_killed[target]) in Epoch.FORWARD, "Killed"

    self.burner.push_target()
    amount: uint256 = target.balanceOf(self)

    # Account buffer
    hooker: Hooker = self.hooker
    hooker_buffer: uint256 = hooker.buffer_amount()
    amount -= min(hooker_buffer, amount)

    fee: uint256 = self._fee(Epoch.FORWARD, block.timestamp) * amount / ONE
    target.transfer(_receiver, fee)

    target.transfer(hooker.address, amount - fee)
    if self.last_hooker_approve < (block.timestamp - START_TIME) / WEEK:  # First time this week
        assert target.approve(hooker.address, hooker_buffer, default_return_value=True)
        self.last_hooker_approve = (block.timestamp - START_TIME) / WEEK
    fee += hooker.duty_act(_hook_inputs, _receiver, value=msg.value)

    return fee


@external
def recover(_recovers: DynArray[RecoverInput, MAX_LEN], _receiver: address):
    """
    @notice Recover ERC20 tokens or Ether from this contract
    @dev Callable only by owner and emergency owner
    @param _recovers (Token, amount) to recover
    @param _receiver Receiver of coins
    """
    assert msg.sender in [self.owner, self.emergency_owner], "Only owner"

    for input in _recovers:
        amount: uint256 = input.amount
        if input.coin.address == ETH_ADDRESS:
            if amount == max_value(uint256):
                amount = self.balance
            raw_call(_receiver, b"", value=amount)
        else:
            if amount == max_value(uint256):
                amount = input.coin.balanceOf(self)
            input.coin.transfer(_receiver, amount, default_return_value=True)  # do not need safe transfer


@external
def set_max_fee(_epoch: Epoch, _max_fee: uint256):
    """
    @notice Set keeper's max fee
    @dev Callable only by owner
    @param _epoch Epoch to set fee for
    @param _max_fee Maximum fee to set
    """
    assert msg.sender == self.owner, "Only owner"
    subset: uint256 = convert(_epoch, uint256)
    assert subset & (subset - 1) == 0, "Bad Epoch"
    assert _max_fee <= ONE, "Bad max_fee"
    self.max_fee[convert(_epoch, uint256)] = _max_fee

    log SetMaxFee(_epoch, _max_fee)


@external
def set_burner(_new_burner: Burner):
    """
    @notice Set burner for exchanging coins, must implement BURNER_INTERFACE
    @dev Callable only by owner
    @param _new_burner Address of the new contract
    """
    assert msg.sender == self.owner, "Only owner"
    assert _new_burner.supportsInterface(BURNER_INTERFACE_ID)
    self.burner = _new_burner

    log SetBurner(_new_burner)


@external
def set_hooker(_new_hooker: Hooker):
    """
    @notice Set contract for hooks, must implement HOOKER_INTERFACE
    @dev Callable only by owner
    @param _new_hooker Address of the new contract
    """
    assert msg.sender == self.owner, "Only owner"
    assert _new_hooker.supportsInterface(HOOKER_INTERFACE_ID)

    if self.hooker != empty(Hooker):
        self.target.approve(self.hooker.address, 0)
    self.hooker = _new_hooker

    log SetHooker(_new_hooker)


@external
def set_target(_new_target: ERC20):
    """
    @notice Set new coin for fees accumulation
    @dev Callable only by owner
    @param _new_target Address of the new target coin
    """
    assert msg.sender == self.owner, "Only owner"

    target: ERC20 = self.target
    self.is_killed[target] = empty(Epoch)  # allow to collect and exchange
    log SetKilled(target, empty(Epoch))

    self.target = _new_target
    self.is_killed[_new_target] = Epoch.COLLECT | Epoch.EXCHANGE  # Keep target coin in contract
    log SetTarget(_new_target)
    log SetKilled(_new_target, Epoch.COLLECT | Epoch.EXCHANGE)


@external
def set_killed(_input: DynArray[KilledInput, MAX_LEN]):
    """
    @notice Stop a contract or specific coin to be burnt
    @dev Callable only by owner or emergency owner
    @param _input Array of (coin address, killed phases enum)
    """
    assert msg.sender in [self.owner, self.emergency_owner], "Only owner"

    for input in _input:
        self.is_killed[input.coin] = input.killed
        log SetKilled(input.coin, input.killed)


@external
def set_owner(_new_owner: address):
    """
    @notice Set owner of the contract
    @dev Callable only by current owner
    @param _new_owner Address of the new owner
    """
    assert msg.sender == self.owner, "Only owner"
    assert _new_owner != empty(address)
    self.owner = _new_owner
    log SetOwner(_new_owner)


@external
def set_emergency_owner(_new_owner: address):
    """
    @notice Set emergency owner of the contract
    @dev Callable only by current owner
    @param _new_owner Address of the new emergency owner
    """
    assert msg.sender == self.owner, "Only owner"
    assert _new_owner != empty(address)
    self.emergency_owner = _new_owner
    log SetEmergencyOwner(_new_owner)