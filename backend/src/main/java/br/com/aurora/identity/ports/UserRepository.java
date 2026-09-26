package br.com.aurora.identity.ports;

import br.com.aurora.identity.domain.*;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/** Persistência de identidade. O domínio depende desta interface, não de SQL. */
public interface UserRepository {

    void save(User user);
    void updateStatus(UUID userId, UserStatus status);
    void savePinHash(UUID userId, String pinHash);

    Optional<User> findById(UUID id);
    Optional<User> findByCpf(String cpf);
    Optional<String> findPinHash(UUID userId);
    boolean existsByCpf(String cpf);
    boolean existsByEmail(String email);

    // Biometria
    void saveEnrollment(FaceEnrollment enrollment, byte[] sealedTemplate, byte[] nonce,
                        String algorithm);
    Optional<SealedEnrollment> findActiveEnrollment(UUID userId);
    void recordVerification(UUID userId, UUID enrollmentId, FaceMatch match, UUID deviceId);

    /** Template ainda cifrado, como está no banco. */
    record SealedEnrollment(UUID id, UUID userId, byte[] ciphertext, byte[] nonce,
                            String algorithm, boolean livenessPassed) {}

    // Dispositivos
    void saveDevice(Device device);
    void updateDeviceStatus(UUID deviceId, DeviceStatus status);
    void touchDevice(UUID deviceId);
    Optional<Device> findDevice(UUID userId, String hardwareId);
    List<Device> listDevices(UUID userId);
}
