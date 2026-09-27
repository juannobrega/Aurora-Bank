package br.com.aurora.banking.application;

import br.com.aurora.banking.domain.*;
import br.com.aurora.banking.ports.BankingRepository;
import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;
import br.com.aurora.shared.time.AuroraClock;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalTime;
import java.util.List;
import java.util.UUID;

/** Envio e recebimento de Pix, chaves e limites. */
@Service
public class PixService {

    /** Limite entre 20h e 6h, como o app já sinalizava. */
    private static final Money NIGHT_LIMIT = Money.of("1000.00");

    private final MoneyMover mover;
    private final BankingRepository banking;
    private final AuroraClock clock;

    public PixService(MoneyMover mover, BankingRepository banking, AuroraClock clock) {
        this.mover = mover;
        this.banking = banking;
        this.clock = clock;
    }

    public record SendCommand(UUID userId, String pixKey, Money amount, String note) {}

    @Transactional
    public BankTransaction send(SendCommand cmd) {
        if (isNight() && cmd.amount().isGreaterThan(NIGHT_LIMIT)) {
            throw new DomainException(ErrorCode.LIMITE_NOTURNO_EXCEDIDO,
                    "Entre 20h e 6h o limite é " + NIGHT_LIMIT + ".");
        }

        var destination = banking.findPixKeyByValue(cmd.pixKey());

        // Enviar para a própria chave produziria uma transação com origem e
        // destino iguais, que o razão recusa — melhor dizer isso claramente
        // do que devolver erro interno.
        if (destination.isPresent() && destination.get().userId().equals(cmd.userId())) {
            throw new DomainException(ErrorCode.PIX_PARA_SI_MESMO);
        }

        // Se a chave é de outro usuário daqui, o dinheiro vai direto para a
        // conta dele; senão sai pela conta de liquidação, rumo a outro banco.
        UUID toAccount = destination
                .map(k -> banking.checkingAccountOf(k.userId()))
                .orElseGet(banking::settlementAccount);

        String counterparty = destination
                .map(k -> "Chave " + maskKey(k.value()))
                .orElse(maskKey(cmd.pixKey()));

        var tx = mover.move(new MoneyMover.Transfer(
                cmd.userId(), banking.checkingAccountOf(cmd.userId()), toAccount,
                cmd.amount(), "PIX_ENVIADO", "Pix enviado", counterparty,
                TxCategory.transferencia, TxMethod.pix, false, cmd.note()));

        banking.rememberContact(cmd.userId(), counterparty, cmd.pixKey(), "Aurora");

        // O destinatário interno vê a entrada no extrato dele.
        destination.ifPresent(key -> {
            banking.notify(key.userId(), "transaction", "Pix recebido",
                    cmd.amount() + " na sua conta");
        });
        return tx;
    }

    @Transactional
    public BankingRepository.PixKeyRow createKey(UUID userId, String kind, String value) {
        var id = UUID.randomUUID();
        String resolved = "aleatoria".equals(kind)
                ? UUID.randomUUID().toString()
                : value;
        if (resolved == null || resolved.isBlank()) {
            throw new DomainException(ErrorCode.BIOMETRIA_INVALIDA, "Valor da chave vazio.");
        }
        banking.savePixKey(id, userId, kind, resolved);
        return new BankingRepository.PixKeyRow(id, userId, kind, resolved);
    }

    public List<BankingRepository.PixKeyRow> keys(UUID userId) {
        return banking.listPixKeys(userId);
    }

    @Transactional
    public void deleteKey(UUID userId, UUID keyId) {
        banking.deletePixKey(userId, keyId);
    }

    private boolean isNight() {
        int hour = LocalTime.ofInstant(clock.instant(), AuroraClock.BRAZIL).getHour();
        return hour >= 20 || hour < 6;
    }

    /** Mostra só o suficiente para a pessoa reconhecer a chave. */
    static String maskKey(String key) {
        if (key == null || key.length() < 6) return "chave Pix";
        if (key.contains("@")) {
            var parts = key.split("@");
            return parts[0].substring(0, Math.min(2, parts[0].length())) + "***@" + parts[1];
        }
        String digits = key.replaceAll("\\D", "");
        if (digits.length() == 11) {
            return "***." + digits.substring(3, 6) + "." + digits.substring(6, 9) + "-**";
        }
        return key.substring(0, 4) + "…" + key.substring(key.length() - 4);
    }
}
