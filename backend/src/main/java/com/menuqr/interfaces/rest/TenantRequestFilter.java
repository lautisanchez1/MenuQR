package com.menuqr.interfaces.rest;

import com.menuqr.application.shared.TenantContext;
import com.menuqr.domain.tenant.TenantId;
import jakarta.annotation.Priority;
import jakarta.inject.Inject;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.ext.Provider;
import org.eclipse.microprofile.jwt.JsonWebToken;

@Provider
@Priority(Priorities.AUTHENTICATION + 1)
public class TenantRequestFilter implements ContainerRequestFilter {
    
    @Inject
    JsonWebToken jwt;
    
    @Inject
    TenantContext tenantContext;
    
    @Override
    public void filter(ContainerRequestContext requestContext) {
        if (jwt != null && jwt.getRawToken() != null) {
            String tenantIdClaim = jwt.getClaim("tenantId");
            String restaurantName = jwt.getClaim("restaurantName");
            
            if (tenantIdClaim != null) {
                tenantContext.setTenantId(TenantId.of(tenantIdClaim));
                tenantContext.setRestaurantName(restaurantName);
            }
        }
    }
}
