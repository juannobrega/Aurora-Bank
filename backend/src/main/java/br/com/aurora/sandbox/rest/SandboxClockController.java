package br.com.aurora.sandbox.rest;

import br.com.aurora.sandbox.MutableClock;
import br.com.aurora.shared.time.AuroraClock;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.NotNull;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;

/**
 * Controle do tempo no sandbox.
 *
 * <p>É o que diferencia este banco de um ambiente de testes comum: dá para
 * ver um mês inteiro acontecer em dois segundos — fatura fechando, parcela
 * vencendo, rendimento caindo.
 */
@RestController
@RequestMapping("/v1/sandbox/clock")
@Tag(name = "Sandbox", description = "Controle do tempo, semente e reset")
public class SandboxClockController {

    private final MutableClock clock;

    public SandboxClockController(MutableClock clock) {
        this.clock = clock;
    }

    public record ClockState(Instant now, LocalDate today, String timezone) {
        static ClockState of(AuroraClock clock) {
            return new ClockState(clock.instant(), clock.today(),
                    AuroraClock.BRAZIL.getId());
        }
    }

    public record AdvanceRequest(@NotNull String duration) {}
    public record SetRequest(@NotNull String instant) {}

    @GetMapping
    @Operation(summary = "Que horas são no mundo simulado")
    public ClockState current() {
        return ClockState.of(clock);
    }

    /**
     * @param request duração no formato ISO-8601: {@code P30D} (30 dias),
     *                {@code PT2H} (2 horas), {@code P1M} não é aceito pelo
     *                {@link Duration} — use {@code P30D}.
     */
    @PostMapping("/advance")
    @Operation(summary = "Avança o relógio (ex.: P30D, PT12H)")
    public ResponseEntity<?> advance(@RequestBody AdvanceRequest request) {
        Duration duration;
        try {
            duration = Duration.parse(request.duration());
        } catch (DateTimeParseException e) {
            return ResponseEntity.badRequest().body(new ApiError(
                    "DURACAO_INVALIDA",
                    "Use o formato ISO-8601 de duração, como P30D ou PT12H."));
        }
        if (duration.isNegative()) {
            return ResponseEntity.badRequest().body(new ApiError(
                    "DURACAO_NEGATIVA",
                    "O relógio não anda para trás. Use /set para voltar no tempo."));
        }
        clock.advance(duration);
        return ResponseEntity.ok(ClockState.of(clock));
    }

    @PostMapping("/set")
    @Operation(summary = "Fixa o relógio num instante")
    public ResponseEntity<?> set(@RequestBody SetRequest request) {
        try {
            clock.set(Instant.parse(request.instant()));
        } catch (DateTimeParseException e) {
            return ResponseEntity.badRequest().body(new ApiError(
                    "INSTANTE_INVALIDO",
                    "Use ISO-8601 em UTC, como 2026-12-31T23:59:00Z."));
        }
        return ResponseEntity.ok(ClockState.of(clock));
    }

    @PostMapping("/reset")
    @Operation(summary = "Devolve o relógio ao tempo real")
    public ClockState reset() {
        clock.reset();
        return ClockState.of(clock);
    }

    public record ApiError(String code, String message) {}
}
