package br.com.aurora.banking.application;

import br.com.aurora.banking.domain.*;
import br.com.aurora.banking.ports.BankingRepository;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * Cofrinhos.
 *
 * <p>Guardar dinheiro não é somar um campo: é mover da conta corrente para
 * a conta do cofrinho. Por isso a soma de todas as contas continua batendo,
 * e resgatar é só o movimento inverso.
 */
@Service
public class GoalService {

    private final MoneyMover mover;
    private final BankingRepository banking;

    public GoalService(MoneyMover mover, BankingRepository banking) {
        this.mover = mover;
        this.banking = banking;
    }

    @Transactional
    public Goal create(UUID userId, String name, Money target, String symbol,
                       LocalDate deadline) {
        if (!target.isPositive()) {
            throw new DomainException(ErrorCode.VALOR_NAO_POSITIVO,
                    "A meta precisa ser maior que zero.");
        }
        var accountId = banking.createGoalAccount(userId, name);
        var goal = new Goal(UUID.randomUUID(), userId, accountId, name,
                target, Money.ZERO, symbol, deadline);
        banking.saveGoal(goal);
        return goal;
    }

    public List<Goal> list(UUID userId) {
        return banking.listGoals(userId);
    }

    @Transactional
    public BankTransaction deposit(UUID userId, UUID goalId, Money amount) {
        var goal = require(userId, goalId);
        return mover.move(new MoneyMover.Transfer(
                userId, banking.checkingAccountOf(userId), goal.accountId(), amount,
                "COFRINHO_DEPOSITO", "Guardado no cofrinho", goal.name(),
                TxCategory.investimento, TxMethod.cofrinho, false, null));
    }

    @Transactional
    public BankTransaction withdraw(UUID userId, UUID goalId, Money amount) {
        var goal = require(userId, goalId);
        // A conta do cofrinho não permite saldo negativo, então tirar mais
        // do que tem falha aqui com SALDO_INSUFICIENTE — sem precisar de
        // verificação própria.
        return mover.move(new MoneyMover.Transfer(
                userId, goal.accountId(), banking.checkingAccountOf(userId), amount,
                "COFRINHO_RESGATE", "Resgate do cofrinho", goal.name(),
                TxCategory.investimento, TxMethod.cofrinho, true, null));
    }

    /** Arquiva devolvendo o que estava guardado. */
    @Transactional
    public void delete(UUID userId, UUID goalId) {
        var goal = require(userId, goalId);
        if (goal.saved().isPositive()) {
            withdraw(userId, goalId, goal.saved());
        }
        banking.archiveGoal(goalId);
    }

    private Goal require(UUID userId, UUID goalId) {
        return banking.findGoal(userId, goalId)
                .orElseThrow(() -> new DomainException(ErrorCode.CONTA_NAO_ENCONTRADA,
                        "Cofrinho não encontrado."));
    }
}
