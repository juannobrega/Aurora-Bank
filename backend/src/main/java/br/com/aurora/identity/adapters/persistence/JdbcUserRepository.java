package br.com.aurora.identity.adapters.persistence;

import br.com.aurora.identity.domain.*;
import br.com.aurora.identity.ports.UserRepository;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.Timestamp;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@Repository
public class JdbcUserRepository implements UserRepository {

    private final NamedParameterJdbcTemplate jdbc;

    public JdbcUserRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    // ------------------------------------------------------------ usuário

    @Override
    public void save(User u) {
        jdbc.update("""
            INSERT INTO users (id, full_name, cpf, email, phone, birth_date, status)
            VALUES (:id, :name, :cpf, :email, :phone, :birth,
                    CAST(:status AS user_status))
            """,
            new MapSqlParameterSource()
                .addValue("id", u.id())
                .addValue("name", u.fullName())
                .addValue("cpf", u.cpf())
                .addValue("email", u.email())
                .addValue("phone", u.phone())
                .addValue("birth", u.birthDate() == null ? null : java.sql.Date.valueOf(u.birthDate()))
                .addValue("status", u.status().name()));
    }

    @Override
    public void updateStatus(UUID userId, UserStatus status) {
        jdbc.update("""
            UPDATE users SET status = CAST(:status AS user_status), updated_at = now()
             WHERE id = :id
            """, Map.of("id", userId, "status", status.name()));
    }

    @Override
    public void savePinHash(UUID userId, String pinHash) {
        jdbc.update("""
            UPDATE users
               SET pin_hash = :hash, pin_updated_at = now(),
                   failed_pin_attempts = 0, locked_until = NULL, updated_at = now()
             WHERE id = :id
            """, Map.of("id", userId, "hash", pinHash));
    }

    @Override
    public Optional<User> findById(UUID id) {
        return jdbc.query("SELECT * FROM users WHERE id = :id",
                Map.of("id", id), USER_MAPPER).stream().findFirst();
    }

    @Override
    public Optional<User> findByCpf(String cpf) {
        return jdbc.query("SELECT * FROM users WHERE cpf = :cpf",
                Map.of("cpf", cpf), USER_MAPPER).stream().findFirst();
    }

    @Override
    public Optional<String> findPinHash(UUID userId) {
        var rows = jdbc.queryForList("SELECT pin_hash FROM users WHERE id = :id",
                Map.of("id", userId), String.class);
        return rows.stream().findFirst();
    }

    @Override
    public boolean existsByCpf(String cpf) {
        return Boolean.TRUE.equals(jdbc.queryForObject(
                "SELECT EXISTS(SELECT 1 FROM users WHERE cpf = :cpf)",
                Map.of("cpf", cpf), Boolean.class));
    }

    @Override
    public boolean existsByEmail(String email) {
        return Boolean.TRUE.equals(jdbc.queryForObject(
                "SELECT EXISTS(SELECT 1 FROM users WHERE email = :email)",
                Map.of("email", email), Boolean.class));
    }

    // ---------------------------------------------------------- biometria

    @Override
    public void saveEnrollment(FaceEnrollment e, byte[] sealed, byte[] nonce, String algorithm) {
        jdbc.update("""
            INSERT INTO face_enrollments (id, user_id, template, template_nonce,
                                          algorithm, quality, liveness_passed)
            VALUES (:id, :user, :template, :nonce, :algo, :quality, :liveness)
            """,
            new MapSqlParameterSource()
                .addValue("id", e.id())
                .addValue("user", e.userId())
                .addValue("template", sealed)
                .addValue("nonce", nonce)
                .addValue("algo", algorithm)
                .addValue("quality", e.quality())
                .addValue("liveness", e.livenessPassed()));
    }

    @Override
    public Optional<SealedEnrollment> findActiveEnrollment(UUID userId) {
        return jdbc.query("""
            SELECT id, user_id, template, template_nonce, algorithm, liveness_passed
              FROM face_enrollments
             WHERE user_id = :user AND revoked_at IS NULL
            """,
            Map.of("user", userId),
            (rs, n) -> new SealedEnrollment(
                    rs.getObject("id", UUID.class),
                    rs.getObject("user_id", UUID.class),
                    rs.getBytes("template"),
                    rs.getBytes("template_nonce"),
                    rs.getString("algorithm"),
                    rs.getBoolean("liveness_passed")))
            .stream().findFirst();
    }

    @Override
    public void recordVerification(UUID userId, UUID enrollmentId, FaceMatch match, UUID deviceId) {
        jdbc.update("""
            INSERT INTO face_verifications (id, user_id, enrollment_id, succeeded,
                                            score, liveness_passed, device_id, failure_reason)
            VALUES (:id, :user, :enrollment, :ok, :score, :liveness, :device, :reason)
            """,
            new MapSqlParameterSource()
                .addValue("id", UUID.randomUUID())
                .addValue("user", userId)
                .addValue("enrollment", enrollmentId)
                .addValue("ok", match.matches())
                .addValue("score", match.distance())
                .addValue("liveness", match.livenessPassed())
                .addValue("device", deviceId)
                .addValue("reason", match.failureReason()));
    }

    // -------------------------------------------------------- dispositivos

    @Override
    public void saveDevice(Device d) {
        jdbc.update("""
            INSERT INTO devices (id, user_id, hardware_id, name, model, os_version,
                                 public_key, status, last_seen_at)
            VALUES (:id, :user, :hw, :name, :model, :os, :key,
                    CAST(:status AS device_status), now())
            ON CONFLICT (user_id, hardware_id) DO UPDATE
               SET name = EXCLUDED.name, model = EXCLUDED.model,
                   os_version = EXCLUDED.os_version,
                   public_key = COALESCE(EXCLUDED.public_key, devices.public_key),
                   last_seen_at = now()
            """,
            new MapSqlParameterSource()
                .addValue("id", d.id())
                .addValue("user", d.userId())
                .addValue("hw", d.hardwareId())
                .addValue("name", d.name())
                .addValue("model", d.model())
                .addValue("os", d.osVersion())
                .addValue("key", d.publicKey())
                .addValue("status", d.status().name()));
    }

    @Override
    public void updateDeviceStatus(UUID deviceId, DeviceStatus status) {
        jdbc.update("""
            UPDATE devices
               SET status = CAST(:status AS device_status),
                   revoked_at = CASE WHEN :status = 'REVOKED' THEN now() ELSE revoked_at END
             WHERE id = :id
            """, Map.of("id", deviceId, "status", status.name()));
    }

    @Override
    public void touchDevice(UUID deviceId) {
        jdbc.update("UPDATE devices SET last_seen_at = now() WHERE id = :id",
                Map.of("id", deviceId));
    }

    @Override
    public Optional<Device> findDevice(UUID userId, String hardwareId) {
        return jdbc.query("""
            SELECT * FROM devices WHERE user_id = :user AND hardware_id = :hw
            """, Map.of("user", userId, "hw", hardwareId), DEVICE_MAPPER)
            .stream().findFirst();
    }

    @Override
    public List<Device> listDevices(UUID userId) {
        return jdbc.query("""
            SELECT * FROM devices WHERE user_id = :user ORDER BY registered_at DESC
            """, Map.of("user", userId), DEVICE_MAPPER);
    }

    // ------------------------------------------------------------ mappers

    private static final RowMapper<User> USER_MAPPER = (rs, n) -> new User(
            rs.getObject("id", UUID.class),
            rs.getString("full_name"),
            rs.getString("cpf"),
            rs.getString("email"),
            rs.getString("phone"),
            rs.getDate("birth_date") == null ? null : rs.getDate("birth_date").toLocalDate(),
            UserStatus.valueOf(rs.getString("status")),
            rs.getTimestamp("created_at").toInstant());

    private static final RowMapper<Device> DEVICE_MAPPER = (rs, n) -> {
        Timestamp seen = rs.getTimestamp("last_seen_at");
        return new Device(
                rs.getObject("id", UUID.class),
                rs.getObject("user_id", UUID.class),
                rs.getString("hardware_id"),
                rs.getString("name"),
                rs.getString("model"),
                rs.getString("os_version"),
                rs.getString("public_key"),
                DeviceStatus.valueOf(rs.getString("status")),
                seen == null ? null : seen.toInstant(),
                rs.getTimestamp("registered_at").toInstant());
    };
}
