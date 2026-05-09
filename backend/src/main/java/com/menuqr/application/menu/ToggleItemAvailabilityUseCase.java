package com.menuqr.application.menu;

import com.menuqr.application.shared.TenantContext;
import com.menuqr.domain.menu.MenuItem;
import com.menuqr.domain.menu.MenuRepository;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;

import java.util.UUID;

@ApplicationScoped
public class ToggleItemAvailabilityUseCase {
    
    @Inject
    MenuRepository menuRepository;
    
    @Inject
    TenantContext tenantContext;
    
    @Transactional
    public void execute(UUID itemId, boolean available) {
        if (!menuRepository.itemBelongsToTenant(itemId, tenantContext.getTenantId())) {
            throw new ItemNotFoundException("Item not found");
        }
        
        MenuItem item = menuRepository.findItemById(itemId)
            .orElseThrow(() -> new ItemNotFoundException("Item not found"));
        
        item.setAvailable(available);
        menuRepository.updateItem(item);
    }
    
    public static class ItemNotFoundException extends RuntimeException {
        public ItemNotFoundException(String message) {
            super(message);
        }
    }
}
