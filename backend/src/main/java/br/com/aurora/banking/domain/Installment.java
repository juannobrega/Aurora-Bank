package br.com.aurora.banking.domain;

import br.com.aurora.shared.money.Money;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

public record Installment(UUID id, UUID loanId, int number, Money amount,
                          LocalDate dueDate, Instant paidAt) {

    public boolean isPaid() { return paidAt != null; }

    public boolean isOverdue(LocalDate today) {
        return !isPaid() && dueDate.isBefore(today);
    }
}
