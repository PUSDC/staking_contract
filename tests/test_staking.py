import pytest
from brownie import BBSStaking, Erc20, MockAave, accounts, reverts

# Fixtures provide setup for each test
@pytest.fixture
def mock_usdc(Erc20, accounts):
    # Constructor: _initialAmount, _tokenName, _decimalUnits, _tokenSymbol
    initial_supply = 1_000_000 * 10**6
    return Erc20.deploy(initial_supply, "Mock USDC", 6, "USDC", {'from': accounts[0]})

@pytest.fixture
def mock_aave(MockAave, accounts):
    return MockAave.deploy({'from': accounts[0]})

@pytest.fixture
def staking_contract(BBSStaking, mock_usdc, mock_aave, accounts):
    # Constructor: _erc20, _aave (now only 2 parameters)
    return BBSStaking.deploy(
        mock_usdc.address, 
        mock_aave.address, 
        {'from': accounts[0]}
    )

def test_initial_deployment(staking_contract, mock_usdc, mock_aave, accounts):
    assert staking_contract.owner() == accounts[0].address
    assert staking_contract.erc20() == mock_usdc.address
    assert staking_contract.aave() == mock_aave.address
    assert staking_contract.minDeposit() == 0

def test_owner_set_min_deposit(staking_contract, accounts):
    min_amount = 100 * 10**6
    # Only owner can set
    staking_contract.setMinDeposit(min_amount, {'from': accounts[0]})
    assert staking_contract.minDeposit() == min_amount
    
    # Non-owner should fail
    # Use reverts() without string to avoid "Unexpected revert string 'None'"
    with reverts():
        staking_contract.setMinDeposit(200 * 10**6, {'from': accounts[1]})

def test_user_deposit(staking_contract, mock_usdc, accounts):
    user = accounts[1]
    amount = 500 * 10**6
    
    #給予用戶代幣
    mock_usdc.transfer(user, amount, {'from': accounts[0]})
    
    # 授權 (Approve)
    mock_usdc.approve(staking_contract.address, amount, {'from': user})
    
    # 存款质押
    tx = staking_contract.deposit(amount, {'from': user})
    
    assert staking_contract.stakedBalances(user) == amount
    assert staking_contract.totalStaked() == amount
    
    # 检查事件
    assert 'Deposited' in tx.events
    assert tx.events['Deposited']['user'] == user.address
    assert tx.events['Deposited']['amount'] == amount

def test_min_deposit_limit(staking_contract, mock_usdc, accounts):
    user = accounts[1]
    min_amount = 1000 * 10**6
    deposit_amount = 500 * 10**6
    
    staking_contract.setMinDeposit(min_amount, {'from': accounts[0]})
    mock_usdc.transfer(user, deposit_amount, {'from': accounts[0]})
    mock_usdc.approve(staking_contract.address, deposit_amount, {'from': user})
    
    # 预期失败：金额低于最小限制度
    with reverts():
        staking_contract.deposit(deposit_amount, {'from': user})

def test_user_withdraw(staking_contract, mock_usdc, accounts):
    user = accounts[1]
    initial_amount = 1000 * 10**6
    withdraw_amount = 250 * 10**6
    
    # 初始化账户并存款
    mock_usdc.transfer(user, initial_amount, {'from': accounts[0]})
    mock_usdc.approve(staking_contract.address, initial_amount, {'from': user})
    staking_contract.deposit(initial_amount, {'from': user})
    
    # 提取質押
    tx = staking_contract.withdraw(withdraw_amount, {'from': user})
    
    assert staking_contract.stakedBalances(user) == initial_amount - withdraw_amount
    assert staking_contract.totalStaked() == initial_amount - withdraw_amount
    
    # 检查事件
    assert 'Withdrawn' in tx.events
    assert tx.events['Withdrawn']['user'] == user.address
    assert tx.events['Withdrawn']['amount'] == withdraw_amount

def test_withdraw_insufficient_balance(staking_contract, mock_usdc, accounts):
    user = accounts[1]
    amount = 500 * 10**6
    
    mock_usdc.transfer(user, amount, {'from': accounts[0]})
    mock_usdc.approve(staking_contract.address, amount, {'from': user})
    staking_contract.deposit(amount, {'from': user})
    
    # 尝试提取超过余额的金额
    with reverts():
        staking_contract.withdraw(amount + 1, {'from': user})

def test_change_owner(staking_contract, accounts):
    new_owner = accounts[1]
    staking_contract.setOwner(new_owner, {'from': accounts[0]})
    assert staking_contract.owner() == new_owner
    
    # 原所有者不能再修改
    with reverts():
        staking_contract.setMinDeposit(100, {'from': accounts[0]})
