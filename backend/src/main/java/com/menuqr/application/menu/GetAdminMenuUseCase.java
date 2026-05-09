package com.menuqr.application.menu;

import com.menuqr.application.shared.TenantContext;
import com.menuqr.domain.menu.Menu;
import com.menuqr.domain.menu.MenuRepository;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

@ApplicationScoped
public class GetAdminMenuUseCase {
    
    @Inject
    MenuRepository menuRepository;
    
    @Inject
    TenantContext tenantContext;
    
    public Menu execute() {
        return menuRepository.findByTenantId(tenantContext.getTenantId());
    }
}
