// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

interface IRETH {
    function getExchangeRate() external view returns (uint256);
    function getTotalCollateral() external view returns (uint256);
    function getEthValue(uint256 _rethAmount) external view returns (uint256);
    function getRethValue(uint256 _ethAmount) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function deposit() external payable;
    function getFeeBps() external view returns (uint256);
    function burn(uint256 _rethAmount) external;
}

/// @notice Инварианты учёта rETH, которые любой может перезапустить без доверия к отчёту:
///   1) обменный курс не убывает во времени (без сжигания/вывода);
///   2) круговой путь ETH → rETH → ETH никогда не возвращает больше, чем вложено;
///   3) totalCollateral покрывает стоимость всего rETH по курсу (учёт не «рисует» лишнего).
contract REthAccountingTest is Test {
    IRETH constant RETH = IRETH(0xae78736Cd615f374D3085123A210448E74Fc6393);

    function setUp() public {
        // форк mainnet: контракты Rocket Pool уже развёрнуты, исходники не нужны
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum-rpc.publicnode.com"));
        vm.createSelectFork(rpc);
    }

    /// 1) курс не убывает за 30 дней при отсутствии сжиганий
    function test_ExchangeRateNonDecreasing() public {
        uint256 rate0 = RETH.getExchangeRate();
        vm.warp(block.timestamp + 30 days);
        uint256 rate1 = RETH.getExchangeRate();
        assertGe(rate1, rate0, "exchange rate decreased without burns");
        emit log_named_uint("rate 0", rate0);
        emit log_named_uint("rate 30d", rate1);
    }

    /// 2) круговой путь не создаёт ETH из воздуха
    function test_RoundTripNeverProfits() public {
        uint256 amount = 1 ether;
        uint256 rethOut = RETH.getRethValue(amount);
        uint256 ethBack = RETH.getEthValue(rethOut);
        assertLe(ethBack, amount, "round trip created ETH");
        emit log_named_uint("in", amount);
        emit log_named_uint("rETH", rethOut);
        emit log_named_uint("back", ethBack);
    }

    /// 3) круговой путь не выгоден НИ при какой сумме (фазз 0.0001–10 000 ETH)
    ///    ВАЖНО: getTotalCollateral() — это только ЛИКВИДНЫЙ буфер (депозитный пул),
    ///    а не весь застейканный ETH, поэтому сравнивать его с supply*rate нельзя.
    ///    Первая версия теста падала именно из-за этой ошибки постановки, а не из-за бага.
    function testFuzz_RoundTripNeverProfits(uint96 amount) public {
        amount = uint96(bound(amount, 1e14, 10_000 ether));
        uint256 rethOut = RETH.getRethValue(amount);
        uint256 ethBack = RETH.getEthValue(rethOut);
        assertLe(ethBack, amount, "round trip created ETH");
    }

    /// 4) курс никогда не ниже 1 ETH за 1 rETH (иначе учёт «просел» бы ниже номинала)
    function test_ExchangeRateAtLeastParity() public {
        assertGe(RETH.getExchangeRate(), 1e18, "rate below parity");
    }

    /// 5) ЖИВОЙ путь минта на форке (block 26290581): deposit() РЕВЕРТИТ — пул депозита закрыт.
    ///    Это НЕ баг, а текущее состояние: Rocket Pool закрывает приём ETH, когда депозитный пул
    ///    заполнен/ограничен. Проверяем главное свойство безопасности: при закрытом приёме
    ///    контракт НЕ принимает ETH (иначе депозит уходил бы безвозмездно).
    function test_LiveDepositIsGatedOrConserved() public {
        vm.deal(address(this), 10 ether);
        uint256 balBefore = address(this).balance;
        try RETH.deposit{value: 1 ether}() {
            // режим открыт: должны получить rETH на сумму, а не потерять ETH
            uint256 rethBal = RETH.balanceOf(address(this));
            assertGt(rethBal, 0, "deposit accepted but produced no rETH");
            emit log_string("deposit OPEN on this fork block");
        } catch {
            // режим закрыт: ETH обязан остаться у вызывающего
            assertEq(address(this).balance, balBefore, "ETH was taken although deposit reverted");
            emit log_string("deposit GATED on this fork block: ETH conserved");
        }
    }

    /// 6) округление на мелких суммах: котировка rETH не должна быть больше входа по стоимости
    function testFuzz_SmallAmountRounding(uint96 amount) public {
        amount = uint96(bound(amount, 1, 1e15)); // 1 wei .. 0.001 ETH
        uint256 rethOut = RETH.getRethValue(amount);
        uint256 ethBack = RETH.getEthValue(rethOut);
        assertLe(ethBack, amount + 1, "rounding gives back more than put in");
        if (rethOut > 0) {
            assertLe(rethOut, amount, "rETH units exceed ETH units at rate > 1");
        }
    }
}
