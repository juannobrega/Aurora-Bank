package br.com.aurora.identity.domain;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** Pessoa com conta neste ambiente. Cadastro real e persistente. */
public record User(
        UUID id,
        String fullName,
        String cpf,              // só dígitos
        String email,
        String phone,
        LocalDate birthDate,
        UserStatus status,
        Instant createdAt
) {
    public String firstName() {
        var parts = fullName.trim().split("\\s+");
        return parts.length > 0 ? parts[0] : fullName;
    }

    public String initials() {
        var parts = fullName.trim().split("\\s+");
        var sb = new StringBuilder();
        for (int i = 0; i < Math.min(2, parts.length); i++) {
            if (!parts[i].isEmpty()) sb.append(Character.toUpperCase(parts[i].charAt(0)));
        }
        return sb.toString();
    }

    /** CPF mascarado para exibição: ***.917.330-**  */
    public String maskedCpf() {
        if (cpf == null || cpf.length() != 11) return "";
        return "***." + cpf.substring(3, 6) + "." + cpf.substring(6, 9) + "-**";
    }

    public boolean canTransact() {
        return status == UserStatus.ACTIVE;
    }
}
