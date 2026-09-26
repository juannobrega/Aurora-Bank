package br.com.aurora.sandbox;

import br.com.aurora.shared.time.AuroraClock;

import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Relógio controlável do sandbox.
 *
 * <p>É o que permite "avance 30 dias e feche a fatura" em dois segundos.
 * Guarda um deslocamento em relação ao tempo real, em vez de um instante
 * fixo, para que o tempo continue correndo entre um comando e outro.
 */
public final class MutableClock implements AuroraClock.Controllable {

    private final AuroraClock base;
    private final AtomicReference<Duration> offset = new AtomicReference<>(Duration.ZERO);
    /** Quando presente, o relógio fica parado neste instante. */
    private final AtomicReference<Instant> pinned = new AtomicReference<>();

    public MutableClock(AuroraClock base) {
        this.base = base;
    }

    public MutableClock() {
        this(AuroraClock.system());
    }

    @Override
    public Instant instant() {
        Instant fixed = pinned.get();
        return fixed != null ? fixed : base.instant().plus(offset.get());
    }

    @Override
    public void advance(Duration duration) {
        Instant fixed = pinned.get();
        if (fixed != null) {
            pinned.set(fixed.plus(duration));
        } else {
            offset.updateAndGet(current -> current.plus(duration));
        }
    }

    @Override
    public void set(Instant instant) {
        pinned.set(instant);
    }

    @Override
    public void reset() {
        pinned.set(null);
        offset.set(Duration.ZERO);
    }
}
