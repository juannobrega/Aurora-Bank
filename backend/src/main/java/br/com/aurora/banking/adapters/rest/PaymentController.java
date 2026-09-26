package br.com.aurora.banking.adapters.rest;

import br.com.aurora.banking.application.PaymentService;
import br.com.aurora.banking.domain.Boleto;
import br.com.aurora.shared.money.Money;
import br.com.aurora.shared.rest.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;

import static br.com.aurora.banking.adapters.rest.AccountController.TxView;

/** Boletos e recarga de celular. */
@RestController
@RequestMapping("/v1/payments")
@Tag(name = "Pagamentos", description = "Boleto e recarga de celular")
public class PaymentController {

    private final PaymentService payments;

    public PaymentController(PaymentService payments) {
        this.payments = payments;
    }

    // ------------------------------------------------------------- boleto

    public record BoletoView(String digitableLine, String bankCode, String payee,
                             long amountCents, LocalDate dueDate, String kind) {
        static BoletoView of(Boleto b) {
            return new BoletoView(b.digitableLine(), b.bankCode(), b.payee(),
                    b.amount().cents(), b.dueDate(), b.kind().name());
        }
    }

    public record LineRequest(@NotBlank String digitableLine) {}

    @PostMapping("/boleto/inspect")
    @Operation(summary = "Lê a linha digitável",
               description = "Decodifica banco, valor e vencimento sem cobrar nada. "
                           + "Recusa código com dígito verificador errado.")
    public BoletoView inspect(@Valid @RequestBody LineRequest r) {
        return BoletoView.of(payments.inspect(r.digitableLine()));
    }

    @PostMapping("/boleto/pay")
    @Operation(summary = "Paga o boleto")
    public TxView payBoleto(CurrentUser me, @Valid @RequestBody LineRequest r) {
        return TxView.of(payments.payBoleto(me.userId(), r.digitableLine()));
    }

    // ------------------------------------------------------------ recarga

    public record PhoneRequest(@NotBlank String phone) {}

    public record RechargeQuoteView(String phone, String carrier, List<Long> amountsCents) {}

    @PostMapping("/recharge/quote")
    @Operation(summary = "Identifica a operadora e os valores disponíveis")
    public RechargeQuoteView quote(@Valid @RequestBody PhoneRequest r) {
        var q = payments.quoteRecharge(r.phone());
        return new RechargeQuoteView(q.phone(), q.carrier(),
                q.amounts().stream().map(Money::cents).toList());
    }

    public record RechargeRequest(@NotBlank String phone, @Positive long amountCents) {}

    @PostMapping("/recharge")
    @Operation(summary = "Recarrega o celular")
    public TxView recharge(CurrentUser me, @Valid @RequestBody RechargeRequest r) {
        return TxView.of(payments.recharge(me.userId(), r.phone(),
                Money.ofCents(r.amountCents())));
    }
}
