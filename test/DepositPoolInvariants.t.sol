// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

/// @title DepositPoolInvariants — срез M2: границы депозитного пула rETH
/// @notice Три утверждения, которые проверяются на форке mainnet и не требуют доверия к прозе аудита:
///         1. баланс депозитного пула не превышает объявленный максимум;
///         2. общий учтённый ETH сети не меньше баланса депозитного пула;
///         3. курс rETH, который отдаёт токен, совпадает с отношением обеспечения к предложению.
///
///         Адреса НЕ захардкожены: они выводятся из RocketStorage по ключу
///         keccak256("contract.address" + имя). Так тест не разойдётся с реальным деплоем и заодно
///         документирует, откуда берётся каждый контракт.
///
///         Чего этот файл НЕ проверяет (см. NOT-CLAIMED.md): распределение по минипулам, залог
///         операторов, очереди вывода, пути бриджа. Это следующие срезы.

interface IRocketStorage {
    function getAddress(bytes32 _key) external view returns (address);
}

interface IRocketDepositPool {
    function getBalance() external view returns (uint256);
    function getExcessBalance() external view returns (uint256);
}

interface IRocketDAOProtocolSettingsDeposit {
    function getMaximumDepositPoolSize() external view returns (uint256);
}

interface IRocketNetworkBalances {
    function getTotalETHBalance() external view returns (uint256);
}

interface IRocketTokenRETH {
    function getExchangeRate() external view returns (uint256);
    function getTotalCollateral() external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

contract DepositPoolInvariantsTest is Test {
    IRocketStorage constant STORAGE = IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);

    function setUp() public {
        // форк mainnet: контракты Rocket Pool уже развёрнуты, исходники не нужны
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum-rpc.publicnode.com"));
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

    /// @notice 1. Депозитный пул не может держать больше объявленного максимума.
    function test_DepositPoolBalanceWithinMaximum() public {
        IRocketDepositPool pool = IRocketDepositPool(_addr("rocketDepositPool"));
        uint256 balance = pool.getBalance();
        uint256 maxSize = IRocketDAOProtocolSettingsDeposit(_addr("rocketDAOProtocolSettingsDeposit"))
            .getMaximumDepositPoolSize();
        emit log_named_uint("deposit pool balance", balance);
        emit log_named_uint("maximum deposit pool size", maxSize);
        assertLe(balance, maxSize, "deposit pool holds more ETH than its declared maximum");
    }

    /// @notice 2. Учтённый сетью ETH не меньше того, что лежит в депозитном пуле.
    ///         Если это нарушится, пул учитывает ETH, которого нет в общем балансе сети.
    function test_NetworkTotalCoversDepositPool() public {
        uint256 poolBalance = IRocketDepositPool(_addr("rocketDepositPool")).getBalance();
        uint256 total = IRocketNetworkBalances(_addr("rocketNetworkBalances")).getTotalETHBalance();
        emit log_named_uint("pool balance", poolBalance);
        emit log_named_uint("network total ETH", total);
        assertGe(total, poolBalance, "network total ETH is smaller than the deposit pool balance");
    }

    /// @notice 3. Курс rETH соответствует обеспечению, которое сеть учитывает как общий ETH.
    ///         ПЕРВАЯ ВЕРСИЯ ЭТОГО ТЕСТА БЫЛА НЕВЕРНОЙ и это ценный результат: я взял обеспечение из
    ///         `getTotalCollateral()` (вернул 2 645 ETH при курсе 1.17 и предложении 308 566 rETH —
    ///         арифметически невозможно), то есть читал не тот источник. Правильный источник —
    ///         `getTotalETHBalance()` сети: 362 610 ETH. Мораль: тест, проверяющий нашу модель, обязан
    ///         сначала падать, если модель неверна — иначе он проверяет сам себя.
    function test_ExchangeRateMatchesNetworkTotal() public {
        IRocketTokenRETH reth = IRocketTokenRETH(_addr("rocketTokenRETH"));
        uint256 rate = reth.getExchangeRate();
        uint256 supply = reth.totalSupply();
        uint256 total = IRocketNetworkBalances(_addr("rocketNetworkBalances")).getTotalETHBalance();
        uint256 expected = supply == 0 ? 1 ether : (total * 1 ether) / supply;
        emit log_named_uint("rate", rate);
        emit log_named_uint("expected from network total", expected);
        emit log_named_uint("supply", supply);
        emit log_named_uint("network total", total);
        // Допуск 0.1%, и вот почему он нужен: `getTotalETHBalance()` — это ПОСЛЕДНЕЕ обновление оракула
        // (раз в сутки), а `totalSupply()` — текущее значение. Если с момента обновления кто-то сжёг или
        // выпустил rETH, отношение «последний учтённый ETH / текущее предложение» расходится с курсом на
        // величину этого внутридневного движения. На блоке 26 294 800 расхождение 0.0455% — ровно этого
        // порядка. Строгое равенство здесь было бы неверным тестом, а не строгой проверкой.
        assertApproxEqRel(rate, expected, 1e15, "rETH rate diverges from network total / supply");
    }

    /// @notice 4. Избыточный баланс пула неотрицателен по определению, но проверяем, что он не превышает
    ///         сам баланс: excess — это часть баланса, а не независимый счётчик.
    function test_ExcessBalanceSubsetOfBalance() public {
        IRocketDepositPool pool = IRocketDepositPool(_addr("rocketDepositPool"));
        uint256 balance = pool.getBalance();
        uint256 excess = pool.getExcessBalance();
        emit log_named_uint("balance", balance);
        emit log_named_uint("excess", excess);
        assertLe(excess, balance, "excess balance exceeds the total deposit pool balance");
    }
}
