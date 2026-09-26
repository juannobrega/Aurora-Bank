package br.com.aurora.identity.domain;

import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;

/** Validação real de CPF pelos dígitos verificadores. */
public final class Cpf {

    private Cpf() {}

    public static String normalize(String raw) {
        if (raw == null) throw new DomainException(ErrorCode.CPF_INVALIDO);
        String digits = raw.replaceAll("\\D", "");
        if (!isValid(digits)) throw new DomainException(ErrorCode.CPF_INVALIDO);
        return digits;
    }

    public static boolean isValid(String raw) {
        if (raw == null) return false;
        String d = raw.replaceAll("\\D", "");
        if (d.length() != 11) return false;
        // Todos os dígitos iguais passam na conta mas não são CPFs válidos.
        if (d.chars().distinct().count() == 1) return false;

        for (int check = 0; check < 2; check++) {
            int sum = 0;
            int weight = 10 + check;
            for (int i = 0; i < 9 + check; i++) {
                sum += (d.charAt(i) - '0') * (weight - i);
            }
            int rest = (sum * 10) % 11;
            int expected = rest == 10 ? 0 : rest;
            if (expected != d.charAt(9 + check) - '0') return false;
        }
        return true;
    }
}
