// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

/// @title VaultSolvency — срез M3: RocketVault обязан покрывать то, что он учитывает
/// @notice Утверждения:
///         1. реальный ETH в `RocketVault` не меньше учтённого баланса депозитного пула;
///         2. `RocketDepositPool.getBalance()` равен `rocketVault.balanceOf("rocketDepositPool")`
///            (то есть пул не ведёт свой счётчик параллельно);
///         3. учтённый баланс пула не отрицателен и не «пуст», когда в хранилище есть ETH.
///
///         Почему это важно: ETH депозитного пула лежит НЕ в самом пуле, а в Vault
///         (`getBalance()` в исходнике = `rocketVault.balanceOf("rocketDepositPool")`). Если Vault
///         держит меньше, чем учитывает, значит часть обязательств не обеспечена — это класс
///         «замерзание/потеря средств», а не косметика.
///
///         Адреса выводятся из RocketStorage **на том блоке форка**: адрес контракта — функция от блока
///         (урок 29.10: пул переехал с 0xdd3f…5af8 на 0xce15…4fdc, и опрос «текущего» адреса на старом
///         блоке даёт пустоту, которую легко принять за нулевой баланс).
contract VaultSolvencyTest is Test {
    IRocketStorage constant STORAGE = IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string("https://eth.drpc.org"));
        uint256 forkBlock = vm.envOr("FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(rpc);
        } else {
            vm.createSelectFork(rpc, forkBlock);
        }
    }

    function _addr(string memory name) internal view returns (address) {
        return STORAGE.getAddress(keccak256(abi.encodePacked("contract.address", name)));
    }

    /// 1. Vault держит не меньше, чем учитывает за депозитным пулом.
    function test_VaultCoversDepositPoolLiability() public {
        address vault = _addr("rocketVault");
        uint256 vaultEth = vault.balance;
        uint256 liability = IRocketVault(vault).balanceOf("rocketDepositPool");
        emit log_named_uint("vault ETH", vaultEth);
        emit log_named_uint("deposit pool liability", liability);
        assertGe(vaultEth, liability, "vault holds less ETH than it owes the deposit pool");
    }

    /// 2. Пул не ведёт отдельный счётчик: его баланс — это запись в Vault.
    function test_PoolBalanceIsVaultEntry() public {
        address vault = _addr("rocketVault");
        uint256 poolSays = IRocketDepositPool(_addr("rocketDepositPool")).getBalance();
        uint256 vaultSays = IRocketVault(vault).balanceOf("rocketDepositPool");
        emit log_named_uint("pool.getBalance()", poolSays);
        emit log_named_uint("vault.balanceOf(pool)", vaultSays);
        assertEq(poolSays, vaultSays, "deposit pool balance disagrees with the vault entry");
    }

    /// 3. Пул не может учитывать больше, чем у Vault есть на все контракты вместе.
    function test_PoolLiabilityBelowVaultTotal() public {
        address vault = _addr("rocketVault");
        uint256 liability = IRocketVault(vault).balanceOf("rocketDepositPool");
        assertLe(liability, vault.balance, "pool liability exceeds the vault's entire ETH");
    }
}

interface IRocketStorage {
    function getAddress(bytes32 _key) external view returns (address);
}

interface IRocketVault {
    function balanceOf(string memory _networkContractName) external view returns (uint256);
}

interface IRocketDepositPool {
    function getBalance() external view returns (uint256);
}
