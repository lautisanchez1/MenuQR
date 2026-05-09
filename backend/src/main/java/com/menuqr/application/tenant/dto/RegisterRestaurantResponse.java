package com.menuqr.application.tenant.dto;

public record RegisterRestaurantResponse(
    String token,
    String tenantId,
    String restaurantName
) {}
