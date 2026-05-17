package com.menudigital.infrastructure.persistence;

import com.menudigital.infrastructure.persistence.entity.UserEntity;
import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

@ApplicationScoped
public class UserRepositoryImpl implements PanacheRepositoryBase<UserEntity, UUID> {
    
    @Transactional
    public UserEntity createUser(String email, UUID restaurantId) {
        UserEntity user = new UserEntity();
        user.id = UUID.randomUUID();
        user.email = email;
        user.restaurantId = restaurantId;
        user.createdAt = Instant.now();
        persist(user);
        return user;
    }
    
    public Optional<UserEntity> findByEmail(String email) {
        return find("email", email).firstResultOptional();
    }

    public Optional<UserEntity> findByCognitoSub(String cognitoSub) {
        return find("cognitoSub", cognitoSub).firstResultOptional();
    }

    public boolean existsByEmail(String email) {
        return count("email", email) > 0;
    }
}
