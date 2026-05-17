package com.menudigital.application.tenant;

import com.menudigital.application.tenant.dto.RegisterRestaurantCommand;
import com.menudigital.application.tenant.dto.RegisterRestaurantResponse;
import com.menudigital.domain.tenant.Restaurant;
import com.menudigital.domain.tenant.RestaurantRepository;
import com.menudigital.infrastructure.persistence.UserRepositoryImpl;
import io.smallrye.jwt.build.Jwt;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.time.Duration;

@ApplicationScoped
public class RegisterRestaurantUseCase {
    
    @Inject
    RestaurantRepository restaurantRepository;
    
    @Inject
    UserRepositoryImpl userRepository;
    
    @ConfigProperty(name = "mp.jwt.verify.issuer", defaultValue = "menudigital")
    String issuer;
    
    @Transactional
    public RegisterRestaurantResponse execute(RegisterRestaurantCommand command) {
        if (restaurantRepository.existsBySlug(command.slug())) {
            throw new SlugAlreadyExistsException("Slug '" + command.slug() + "' is already taken");
        }
        
        if (userRepository.existsByEmail(command.ownerEmail())) {
            throw new EmailAlreadyExistsException("Email '" + command.ownerEmail() + "' is already registered");
        }
        
        Restaurant restaurant = Restaurant.create(
            command.restaurantName(),
            command.slug(),
            command.ownerEmail()
        );
        restaurantRepository.save(restaurant);

        var user = userRepository.createUser(command.ownerEmail(), restaurant.getId().value());
        
        String token = generateToken(user.id.toString(), restaurant.getId().toString(), restaurant.getName());
        
        return new RegisterRestaurantResponse(
            token,
            restaurant.getId().toString(),
            restaurant.getName()
        );
    }
    
    private String generateToken(String userId, String tenantId, String restaurantName) {
        return Jwt.issuer(issuer)
            .upn(userId)
            .subject(userId)
            .claim("tenantId", tenantId)
            .claim("restaurantName", restaurantName)
            .audience("menudigital-app")
            .expiresIn(Duration.ofHours(24))
            .sign();
    }
    
    public static class SlugAlreadyExistsException extends RuntimeException {
        public SlugAlreadyExistsException(String message) {
            super(message);
        }
    }
    
    public static class EmailAlreadyExistsException extends RuntimeException {
        public EmailAlreadyExistsException(String message) {
            super(message);
        }
    }
}
