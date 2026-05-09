package com.menuqr.application.menu;

import com.menuqr.domain.menu.Menu;
import com.menuqr.domain.menu.MenuRepository;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import java.util.Optional;

@ApplicationScoped
public class GetPublicMenuUseCase {
    
    @Inject
    MenuRepository menuRepository;
    
    public Optional<Menu> execute(String slug) {
        return menuRepository.findBySlug(slug)
            .map(Menu::withOnlyAvailableItems);
    }
}
