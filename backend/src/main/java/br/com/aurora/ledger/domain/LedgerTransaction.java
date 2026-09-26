package br.com.aurora.ledger.domain;

import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import br.com.aurora.shared.money.Money;

import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Transação do razão: um conjunto de lançamentos que soma zero.
 *
 * <p>A invariante I-1 ("a soma dos lançamentos de uma transação é zero") é
 * garantida <b>no construtor</b>. Não existe instante em que um objeto
 * desbalanceado exista na memória — o mesmo vale no banco, por constraint
 * {@code DEFERRABLE}, e há um job de varredura por cima. Redundância aqui é
 * barata; dinheiro sumindo não é.
 */
public final class LedgerTransaction {

    private final UUID id;
    private final UUID tenantId;
    private final String kind;
    private final String description;
    private final Instant occurredAt;
    private final List<Entry> entries;

    private LedgerTransaction(UUID id, UUID tenantId, String kind, String description,
                              Instant occurredAt, List<Entry> entries) {
        this.id = id;
        this.tenantId = tenantId;
        this.kind = kind;
        this.description = description;
        this.occurredAt = occurredAt;
        this.entries = List.copyOf(entries);
    }

    /**
     * Cria a transação, recusando qualquer conjunto de lançamentos inválido.
     *
     * @param occurredAt instante vindo do {@code AuroraClock} — nunca
     *                   {@code Instant.now()}, para que o sandbox possa
     *                   simular datas.
     */
    public static LedgerTransaction of(UUID tenantId, String kind, String description,
                                       Instant occurredAt, List<Entry> entries) {
        if (entries.size() < 2) {
            throw new DomainException(ErrorCode.PERNAS_INSUFICIENTES);
        }
        Set<UUID> accounts = entries.stream().map(Entry::accountId).collect(Collectors.toSet());
        if (accounts.size() < 2) {
            throw new DomainException(ErrorCode.PERNAS_INSUFICIENTES,
                    "Todas as pernas apontam para a mesma conta.");
        }
        if (!sumsToZero(entries)) {
            throw new DomainException(ErrorCode.LANCAMENTO_DESBALANCEADO,
                    "Diferença de " + balanceOf(entries) + ".");
        }
        return new LedgerTransaction(UUID.randomUUID(), tenantId, kind, description,
                occurredAt, entries);
    }

    /** Atalho para o caso mais comum: mover valor de uma conta para outra. */
    public static LedgerTransaction transfer(UUID tenantId, String kind, String description,
                                             Instant occurredAt,
                                             UUID from, UUID to, Money amount) {
        return of(tenantId, kind, description, occurredAt,
                List.of(Entry.debit(from, amount), Entry.credit(to, amount)));
    }

    private static boolean sumsToZero(List<Entry> entries) {
        return balanceOf(entries).isZero();
    }

    private static Money balanceOf(List<Entry> entries) {
        return entries.stream()
                .map(Entry::signedAmount)
                .reduce(Money.ZERO, Money::plus);
    }

    /** Contribuição desta transação ao saldo de uma conta. */
    public Money effectOn(UUID accountId) {
        return entries.stream()
                .filter(e -> e.accountId().equals(accountId))
                .map(Entry::signedAmount)
                .reduce(Money.ZERO, Money::plus);
    }

    public UUID id()               { return id; }
    public UUID tenantId()         { return tenantId; }
    public String kind()           { return kind; }
    public String description()    { return description; }
    public Instant occurredAt()    { return occurredAt; }
    public List<Entry> entries()   { return entries; }
}
