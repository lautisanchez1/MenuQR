package com.menuqr.infrastructure.persistence.entity;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "users")
public class UserEntity extends PanacheEntityBase {
    
    @Id
    public UUID id;
    
    @Column(nullable = false, unique = true)
    public String email;
    
    @Column(name = "password_hash", nullable = false)
    public String passwordHash;
    
    @Column(name = "restaurant_id")
    public UUID restaurantId;
    
    @Column(name = "created_at", nullable = false)
    public Instant createdAt;
}
