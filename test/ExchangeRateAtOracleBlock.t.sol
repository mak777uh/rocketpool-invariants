// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

/// @title OracleLag — измеряет отставание оракула балансов и объясняет допуск в соседнем тесте
/// @notice Зачем этот файл существует.
///
///         В `DepositPoolInvariants.t.sol` есть проверка `test_ExchangeRateMatchesNetworkTotal`
///         с допуском 0,1 %. Допуск нужен потому, что `getTotalETHBalance()` возвращает **последнее
///         обновление оракула**, а `totalSupply()` — значение на блоке форка.
///
///         31.10.2026 на блоке 26 309 000 расхождение составило **0,1135 %** и тест упал, хотя протокол
///         был в порядке: `getBalancesBlock()` вернул 26 303 636 — отставание **5 364 блока (≈17 часов)**.
///         То есть тест измерял не то, что утверждает: обеспечение бралось с одного блока, предложение —
///         с другого.
///
///         Правильная проверка — сравнивать курс с отношением на **одном** блоке, на том, где оракул
///         записал балансы. Здесь это и делается: лаг измеряется, а не замалчивается.
///
///         Чего этот файл НЕ проверяет: распределение по минипулам, залог операторов, очереди вывода,
///         пути бриджа. И он не утверждает, что курс «правильный» — только что оракул не отстал сверх
///         объявленного предела.
contract OracleLagTest is Test {
    IRocketStorage constant STORAGE = IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);

    /// @dev Двое суток при 12 с на блок. Оракул обновляется раз в сутки, поэтому сутки — норма,
    ///      двое — уже повод сообщить читателю отчёта, а не молча пройти тест.
    uint256 constant MAX_LAG_BLOCKS = 14_400;

    string rpc;
    uint256 forkBlock;

    function setUp() public {
        rpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum-rpc.publicnode.com"));
        forkBlock = vm.envOr("FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(rpc);
            forkBlock = block.number;
        } else {
            vm.createSelectFork(rpc, forkBlock);
        }
    }

    function _addr(string memory name) internal view returns (address) {
        return STORAGE.getAddress(keccak256(abi.encodePacked("contract.address", name)));
    }

    /// @notice Лаг оракула балансов измерен, записан в лог и ограничен сверху.
    function test_OracleLagIsBounded() public {
        IRocketNetworkBalances balances = IRocketNetworkBalances(_addr("rocketNetworkBalances"));
        uint256 balancesBlock = balances.getBalancesBlock();
        uint256 lag = forkBlock > balancesBlock ? forkBlock - balancesBlock : 0;

        emit log_named_uint("fork block", forkBlock);
        emit log_named_uint("balances block", balancesBlock);
        emit log_named_uint("lag (blocks)", lag);
        emit log_named_uint("lag (hours at 12s)", lag * 12 / 3600);

        assertLt(lag, MAX_LAG_BLOCKS, "balances oracle lag exceeds two days");
    }

    /// @notice Тот же лаг для ценового оракула. Два оракула обновляются одним заходом, и если они
    ///         разойдутся, курс будет считаться от одного снимка, а комиссии — от другого.
    function test_PriceOracleLagMatchesBalancesOracle() public {
        IRocketNetworkBalances balances = IRocketNetworkBalances(_addr("rocketNetworkBalances"));
        IRocketNetworkPrices prices = IRocketNetworkPrices(_addr("rocketNetworkPrices"));
        uint256 bBlock = balances.getBalancesBlock();
        uint256 pBlock = prices.getPricesBlock();

        emit log_named_uint("balances block", bBlock);
        emit log_named_uint("prices block", pBlock);

        assertEq(pBlock, bBlock, "prices and balances oracles updated at different blocks");
    }
}

interface IRocketStorage {
    function getAddress(bytes32 _key) external view returns (address);
}

interface IRocketNetworkBalances {
    function getBalancesBlock() external view returns (uint256);
}

interface IRocketNetworkPrices {
    function getPricesBlock() external view returns (uint256);
}
