package com.menuqr.application.menu;

import com.menuqr.application.menu.dto.MenuDTOs.CreateItemCommand;
import com.menuqr.application.shared.TenantContext;
import com.menuqr.domain.menu.MenuItem;
import com.menuqr.domain.menu.MenuRepository;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;

import java.util.HashSet;

@ApplicationScoped
public class AddMenuItemUseCase {
    
    @Inject
    MenuRepository menuRepository;
    
    @Inject
    TenantContext tenantContext;
    
    @Transactional
    public MenuItem execute(CreateItemCommand command) {
        if (!menuRepository.sectionBelongsToTenant(command.sectionId(), tenantContext.getTenantId())) {
            throw new SectionNotFoundException("Section not found");
        }
        
        MenuItem item = MenuItem.create(
            command.sectionId(),
            tenantContext.getTenantId(),
            command.name(),
            command.description(),
            command.price(),
            command.imageUrl(),
            command.dietaryTags() != null ? command.dietaryTags() : new HashSet<>(),
            command.displayOrder()
        );
        
        return menuRepository.saveItem(item);
    }
    
    public static class SectionNotFoundException extends RuntimeException {
        public SectionNotFoundException(String message) {
            super(message);
        }
    }
}
