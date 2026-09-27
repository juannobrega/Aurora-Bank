package br.com.aurora.admin;

import br.com.aurora.shared.error.DomainException;
import br.com.aurora.shared.error.ErrorCode;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * API de gestão, consumida pelo painel Manager.
 *
 * <p>Protegida por uma chave de admin no header {@code X-Admin-Key} — separada
 * do JWT dos clientes, porque é outro nível de acesso: quem administra vê
 * todos os usuários e o razão inteiro. Só leitura.
 */
@RestController
@RequestMapping("/admin")
@Tag(name = "Administração", description = "Visão de gestão do sistema (painel Manager)")
public class AdminController {

    private final AdminRepository repo;
    private final String adminKey;

    public AdminController(AdminRepository repo,
                           @Value("${aurora.admin.key}") String adminKey) {
        this.repo = repo;
        this.adminKey = adminKey;
    }

    private void authorize(String key) {
        // Comparação de tempo constante, para não vazar a chave por timing.
        if (key == null || !constantTimeEquals(key, adminKey)) {
            throw new DomainException(ErrorCode.ADMIN_NAO_AUTORIZADO);
        }
    }

    @GetMapping("/metrics")
    @Operation(summary = "Métricas globais do sistema")
    public AdminRepository.Metrics metrics(@RequestHeader(value = "X-Admin-Key", required = false) String key) {
        authorize(key);
        return repo.metrics();
    }

    @GetMapping("/users")
    @Operation(summary = "Lista usuários")
    public List<AdminRepository.UserRow> users(
            @RequestHeader(value = "X-Admin-Key", required = false) String key,
            @RequestParam(defaultValue = "50") int limit,
            @RequestParam(defaultValue = "0") int offset) {
        authorize(key);
        return repo.users(Math.min(limit, 200), Math.max(0, offset));
    }

    @GetMapping("/ledger/health")
    @Operation(summary = "Integridade do razão (deve somar zero)")
    public AdminRepository.LedgerHealth ledgerHealth(
            @RequestHeader(value = "X-Admin-Key", required = false) String key) {
        authorize(key);
        return repo.ledgerHealth();
    }

    @GetMapping("/transactions")
    @Operation(summary = "Transações recentes de todos os usuários")
    public List<AdminRepository.RecentTx> transactions(
            @RequestHeader(value = "X-Admin-Key", required = false) String key,
            @RequestParam(defaultValue = "30") int limit) {
        authorize(key);
        return repo.recentTransactions(Math.min(limit, 100));
    }

    private static boolean constantTimeEquals(String a, String b) {
        if (a.length() != b.length()) return false;
        int diff = 0;
        for (int i = 0; i < a.length(); i++) diff |= a.charAt(i) ^ b.charAt(i);
        return diff == 0;
    }
}
