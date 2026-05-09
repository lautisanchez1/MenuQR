package com.menuqr.application.menu;

import com.menuqr.application.menu.dto.MenuDTOs.CreateSectionCommand;
import com.menuqr.application.shared.TenantContext;
import com.menuqr.domain.menu.MenuRepository;
import com.menuqr.domain.menu.MenuSection;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;

@ApplicationScoped
public class CreateMenuSectionUseCase {
    
    @Inject
    MenuRepository menuRepository;
    
    @Inject
    TenantContext tenantContext;
    
    @Transactional
    public MenuSection execute(CreateSectionCommand command) {
        MenuSection section = MenuSection.create(
            tenantContext.getTenantId(),
            command.name(),
            command.displayOrder()
        );
        return menuRepository.saveSection(section);
    }
}
