package com.menuqr.interfaces.rest.auth;

import com.menuqr.application.tenant.RegisterRestaurantUseCase;
import com.menuqr.application.tenant.dto.RegisterRestaurantCommand;
import com.menuqr.application.tenant.dto.RegisterRestaurantResponse;
import com.menuqr.infrastructure.persistence.UserRepositoryImpl;
import io.smallrye.jwt.build.Jwt;
import jakarta.inject.Inject;
import jakarta.validation.Valid;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;
import org.mindrot.jbcrypt.BCrypt;

import java.time.Duration;

@Path("/api/auth")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
@Tag(name = "Authentication", description = "User registration and login")
public class AuthResource {
    
    @Inject
    RegisterRestaurantUseCase registerRestaurantUseCase;
    
    @Inject
    UserRepositoryImpl userRepository;
    
    @ConfigProperty(name = "mp.jwt.verify.issuer", defaultValue = "menuqr")
    String issuer;
    
    @POST
    @Path("/register")
    @Operation(summary = "Register a new restaurant", description = "Creates a new restaurant account and returns a JWT token")
    @APIResponse(responseCode = "200", description = "Registration successful", 
        content = @Content(schema = @Schema(implementation = RegisterRestaurantResponse.class)))
    @APIResponse(responseCode = "409", description = "Slug or email already exists")
    public Response register(@Valid RegisterRestaurantCommand command) {
        try {
            RegisterRestaurantResponse response = registerRestaurantUseCase.execute(command);
            return Response.ok(response).build();
        } catch (RegisterRestaurantUseCase.SlugAlreadyExistsException e) {
            return Response.status(Response.Status.CONFLICT)
                .entity(new ErrorResponse("SLUG_EXISTS", e.getMessage()))
                .build();
        } catch (RegisterRestaurantUseCase.EmailAlreadyExistsException e) {
            return Response.status(Response.Status.CONFLICT)
                .entity(new ErrorResponse("EMAIL_EXISTS", e.getMessage()))
                .build();
        }
    }
    
    @POST
    @Path("/login")
    @Operation(summary = "Login", description = "Authenticates a user and returns a JWT token")
    @APIResponse(responseCode = "200", description = "Login successful",
        content = @Content(schema = @Schema(implementation = LoginResponse.class)))
    @APIResponse(responseCode = "401", description = "Invalid credentials")
    public Response login(@Valid LoginRequest request) {
        var userOpt = userRepository.findByEmail(request.email());
        
        if (userOpt.isEmpty()) {
            return Response.status(Response.Status.UNAUTHORIZED)
                .entity(new ErrorResponse("INVALID_CREDENTIALS", "Invalid email or password"))
                .build();
        }
        
        var user = userOpt.get();
        
        if (!BCrypt.checkpw(request.password(), user.passwordHash)) {
            return Response.status(Response.Status.UNAUTHORIZED)
                .entity(new ErrorResponse("INVALID_CREDENTIALS", "Invalid email or password"))
                .build();
        }
        
        var restaurant = com.menuqr.infrastructure.persistence.entity.RestaurantEntity
            .findById(user.restaurantId);
        
        if (restaurant == null) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity(new ErrorResponse("NO_RESTAURANT", "User has no associated restaurant"))
                .build();
        }
        
        var restaurantEntity = (com.menuqr.infrastructure.persistence.entity.RestaurantEntity) restaurant;
        
        String token = Jwt.issuer(issuer)
            .upn(user.id.toString())
            .subject(user.id.toString())
            .claim("tenantId", restaurantEntity.id.toString())
            .claim("restaurantName", restaurantEntity.name)
            .audience("menuqr-app")
            .expiresIn(Duration.ofHours(24))
            .sign();
        
        return Response.ok(new LoginResponse(
            token,
            restaurantEntity.id.toString(),
            restaurantEntity.name
        )).build();
    }
    
    public record LoginRequest(String email, String password) {}
    public record LoginResponse(String token, String tenantId, String restaurantName) {}
    public record ErrorResponse(String code, String message) {}
}
