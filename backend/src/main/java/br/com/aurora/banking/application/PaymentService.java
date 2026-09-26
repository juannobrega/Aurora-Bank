package br.com.aurora.banking.application;

import br.com.aurora.banking.domain.*;
import br.com.aurora.banking.ports.BankingRepository;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;
import br.com.aurora.shared.time.AuroraClock;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/** Pagamento de boleto e recarga de celular. */
@Service
public class PaymentService {

    private final MoneyMover mover;
    private final BankingRepository banking;
    private final AuroraClock clock;

    public PaymentService(MoneyMover mover, BankingRepository banking, AuroraClock clock) {
        this.mover = mover;
        this.banking = banking;
        this.clock = clock;
    }

    /** Lê a linha digitável sem cobrar nada — é a tela de conferência. */
    public Boleto inspect(String digitableLine) {
        return Boleto.parse(digitableLine);
    }

    @Transactional
    public BankTransaction payBoleto(UUID userId, String digitableLine) {
        var boleto = Boleto.parse(digitableLine);

        if (boleto.isOverdue(clock.today())) {
            throw new DomainException(ErrorCode.BOLETO_VENCIDO,
                    "Venceu em " + boleto.dueDate() + ".");
        }
        if (!boleto.amount().isPositive()) {
            throw new DomainException(ErrorCode.BOLETO_INVALIDO,
                    "Boleto sem valor definido não pode ser pago pelo app.");
        }
        if (banking.isBoletoPaid(digitableLine.replaceAll("\\D", ""))) {
            throw new DomainException(ErrorCode.BOLETO_JA_PAGO);
        }

        var tx = mover.move(new MoneyMover.Transfer(
                userId, banking.checkingAccountOf(userId), banking.settlementAccount(),
                boleto.amount(), "PAGAMENTO_BOLETO", "Pagamento de boleto",
                boleto.payee(), categoryFor(boleto), TxMethod.boleto, false, null));

        banking.recordBoletoPayment(digitableLine.replaceAll("\\D", ""), tx.id());
        banking.notify(userId, "transaction", "Boleto pago",
                boleto.amount() + " para " + boleto.payee());
        return tx;
    }

    public record RechargeQuote(String phone, String carrier, java.util.List<Money> amounts) {}

    /** Identifica a operadora antes de cobrar. */
    public RechargeQuote quoteRecharge(String phone) {
        String digits = Carrier.validate(phone);
        return new RechargeQuote(Carrier.format(digits),
                Carrier.of(digits).label(), Carrier.ALLOWED_AMOUNTS);
    }

    @Transactional
    public BankTransaction recharge(UUID userId, String phone, Money amount) {
        String digits = Carrier.validate(phone);
        Carrier.checkAmount(amount);
        var carrier = Carrier.of(digits);

        var tx = mover.move(new MoneyMover.Transfer(
                userId, banking.checkingAccountOf(userId), banking.settlementAccount(),
                amount, "RECARGA", "Recarga de celular",
                carrier.label() + " · " + Carrier.format(digits),
                TxCategory.outros, TxMethod.recarga, false, null));

        banking.notify(userId, "transaction", "Recarga feita",
                amount + " para " + Carrier.format(digits));
        return tx;
    }

    /** Conta de consumo vira Moradia; cobrança bancária fica em Outros. */
    private static TxCategory categoryFor(Boleto boleto) {
        return boleto.kind() == Boleto.BoletoKind.ARRECADACAO
                ? TxCategory.moradia : TxCategory.outros;
    }
}
