package com.menudigital.interfaces.rest.auth;

import com.menudigital.application.tenant.RegisterRestaurantUseCase;
import com.menudigital.application.tenant.dto.RegisterRestaurantCommand;
import com.menudigital.application.tenant.dto.RegisterRestaurantRequest;
import com.menudigital.application.tenant.dto.RegisterRestaurantResponse;
import com.menudigital.infrastructure.auth.CognitoTokenVerifier;
import com.menudigital.infrastructure.auth.CognitoTokenVerifier.AuthenticationException;
import com.menudigital.infrastructure.auth.CognitoTokenVerifier.VerifiedIdToken;
import com.menudigital.infrastructure.persistence.UserRepositoryImpl;
import com.menudigital.infrastructure.persistence.entity.RestaurantEntity;
import io.smallrye.jwt.build.Jwt;
import jakarta.inject.Inject;
import jakarta.validation.Valid;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

import java.time.Duration;

@Path("/api/auth")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
@Tag(name = "Authentication", description = "Cognito-backed login and registration")
public class AuthResource {

    @Inject
    RegisterRestaurantUseCase registerRestaurantUseCase;

    @Inject
    UserRepositoryImpl userRepository;

    @Inject
    CognitoTokenVerifier cognitoTokenVerifier;

    @ConfigProperty(name = "mp.jwt.verify.issuer", defaultValue = "menudigital")
    String issuer;

    @POST
    @Path("/register")
    @Operation(summary = "Register a new restaurant",
        description = "Requires a verified Cognito ID token in the Authorization header. Email and Cognito sub are taken from the verified token.")
    @APIResponse(responseCode = "200", description = "Registration successful",
        content = @Content(schema = @Schema(implementation = RegisterRestaurantResponse.class)))
    @APIResponse(responseCode = "401", description = "Missing or invalid Cognito token")
    @APIResponse(responseCode = "409", description = "Slug or email already exists")
    public Response register(@Valid RegisterRestaurantRequest request,
                             @HeaderParam(HttpHeaders.AUTHORIZATION) String authorization) {
        VerifiedIdToken verified;
        try {
            verified = cognitoTokenVerifier.verifyIdTokenHeader(authorization);
        } catch (AuthenticationException e) {
            return unauthorized(e.getMessage());
        }

        try {
            var command = new RegisterRestaurantCommand(
                request.restaurantName(),
                request.slug(),
                verified.email(),
                verified.sub()
            );
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
    @Operation(summary = "Exchange a Cognito ID token for an application session",
        description = "Requires a verified Cognito ID token in the Authorization header. Returns the application JWT for the associated tenant.")
    @APIResponse(responseCode = "200", description = "Login successful",
        content = @Content(schema = @Schema(implementation = LoginResponse.class)))
    @APIResponse(responseCode = "401", description = "Missing or invalid Cognito token, or no account exists for this identity")
    public Response login(@HeaderParam(HttpHeaders.AUTHORIZATION) String authorization) {
        VerifiedIdToken verified;
        try {
            verified = cognitoTokenVerifier.verifyIdTokenHeader(authorization);
        } catch (AuthenticationException e) {
            return unauthorized(e.getMessage());
        }

        var userOpt = userRepository.findByCognitoSubOrEmail(verified.sub(), verified.email());
        if (userOpt.isEmpty()) {
            return Response.status(Response.Status.UNAUTHORIZED)
                .entity(new ErrorResponse("UNKNOWN_USER", "No restaurant account exists for this identity"))
                .build();
        }

        var user = userOpt.get();
        userRepository.linkCognitoSub(user.id, verified.sub());

        var restaurant = (RestaurantEntity) RestaurantEntity.findById(user.restaurantId);
        if (restaurant == null) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity(new ErrorResponse("NO_RESTAURANT", "User has no associated restaurant"))
                .build();
        }

        String token = Jwt.issuer(issuer)
            .upn(user.id.toString())
            .subject(user.id.toString())
            .claim("tenantId", restaurant.id.toString())
            .claim("restaurantName", restaurant.name)
            .audience("menudigital-app")
            .expiresIn(Duration.ofHours(24))
            .sign();

        return Response.ok(new LoginResponse(
            token,
            restaurant.id.toString(),
            restaurant.name
        )).build();
    }

    private Response unauthorized(String message) {
        return Response.status(Response.Status.UNAUTHORIZED)
            .entity(new ErrorResponse("INVALID_TOKEN", message))
            .build();
    }

    public record LoginResponse(String token, String tenantId, String restaurantName) {}
    public record ErrorResponse(String code, String message) {}
}
