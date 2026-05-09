package com.menuqr.application.tenant.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record RegisterRestaurantCommand(
    @NotBlank @Size(min = 2, max = 100)
    String restaurantName,
    
    @NotBlank @Size(min = 3, max = 50)
    @Pattern(regexp = "^[a-z0-9-]+$", message = "Slug must contain only lowercase letters, numbers, and hyphens")
    String slug,
    
    @NotBlank @Email
    String ownerEmail,
    
    @NotBlank @Size(min = 8, max = 100)
    String password
) {}
