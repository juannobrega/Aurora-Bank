package br.com.aurora.identity.domain;

import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;

/** Regras do PIN de 4 dígitos. */
public final class Pin {

    private Pin() {}

    public static void validate(String pin) {
        if (pin == null || !pin.matches("\\d{4}")) {
            throw new DomainException(ErrorCode.PIN_FRACO, "O PIN deve ter 4 dígitos.");
        }
        if (isWeak(pin)) {
            throw new DomainException(ErrorCode.PIN_FRACO);
        }
    }

    /** Recusa repetições (1111) e sequências (1234, 4321). */
    public static boolean isWeak(String pin) {
        int[] d = pin.chars().map(c -> c - '0').toArray();
        if (d.length != 4) return true;

        boolean allSame = true, ascending = true, descending = true;
        for (int i = 1; i < 4; i++) {
            if (d[i] != d[0])     allSame = false;
            if (d[i] != d[i-1]+1) ascending = false;
            if (d[i] != d[i-1]-1) descending = false;
        }
        return allSame || ascending || descending;
    }
}
