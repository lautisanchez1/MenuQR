package com.menuqr.infrastructure.persistence;

import com.menuqr.infrastructure.persistence.entity.UserEntity;
import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

@ApplicationScoped
public class UserRepositoryImpl implements PanacheRepositoryBase<UserEntity, UUID> {
    
    @Transactional
    public UserEntity createUser(String email, String passwordHash, UUID restaurantId) {
        UserEntity user = new UserEntity();
        user.id = UUID.randomUUID();
        user.email = email;
        user.passwordHash = passwordHash;
        user.restaurantId = restaurantId;
        user.createdAt = Instant.now();
        persist(user);
        return user;
    }
    
    public Optional<UserEntity> findByEmail(String email) {
        return find("email", email).firstResultOptional();
    }
    
    public boolean existsByEmail(String email) {
        return count("email", email) > 0;
    }
}
