package br.com.aurora.banking.adapters.rest;

import br.com.aurora.banking.ports.BankingRepository;
import br.com.aurora.shared.rest.CurrentUser;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/** Atendimento: abre chamado de chat, ouvidoria ou suporte. */
@RestController
@RequestMapping("/v1/support")
@Tag(name = "Atendimento", description = "Chamados de suporte e ouvidoria")
public class SupportController {

    private final BankingRepository banking;

    public SupportController(BankingRepository banking) {
        this.banking = banking;
    }

    public record TicketRequest(
            @NotBlank @Pattern(regexp = "CHAT|OUVIDORIA|CHAMADO",
                    message = "Canal deve ser CHAT, OUVIDORIA ou CHAMADO")
            String channel,
            @NotBlank String subject) {}

    public record TicketResponse(String protocol, String message) {}

    @PostMapping("/tickets")
    @Operation(summary = "Abre um chamado")
    public TicketResponse open(CurrentUser me, @Valid @RequestBody TicketRequest r) {
        var protocol = banking.openTicket(me.userId(), r.channel(), r.subject());
        return new TicketResponse(protocol,
                "Chamado aberto. Guarde o protocolo " + protocol + ".");
    }

    @GetMapping("/tickets")
    @Operation(summary = "Meus chamados")
    public List<BankingRepository.TicketRow> list(CurrentUser me) {
        return banking.listTickets(me.userId());
    }
}
