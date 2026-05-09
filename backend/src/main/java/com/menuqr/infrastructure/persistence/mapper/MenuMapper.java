package com.menuqr.infrastructure.persistence.mapper;

import com.menuqr.domain.menu.DietaryTag;
import com.menuqr.domain.menu.Menu;
import com.menuqr.domain.menu.MenuItem;
import com.menuqr.domain.menu.MenuSection;
import com.menuqr.domain.tenant.TenantId;
import com.menuqr.infrastructure.persistence.entity.MenuItemEntity;
import com.menuqr.infrastructure.persistence.entity.MenuSectionEntity;
import com.menuqr.infrastructure.persistence.entity.RestaurantEntity;

import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

public class MenuMapper {
    
    private MenuMapper() {
    }
    
    public static Menu toDomain(RestaurantEntity restaurant, List<MenuSectionEntity> sections) {
        TenantId tenantId = new TenantId(restaurant.id);
        List<MenuSection> domainSections = sections.stream()
            .map(s -> toSectionDomain(s, tenantId))
            .collect(Collectors.toList());
        
        return new Menu(tenantId, restaurant.name, restaurant.slug, domainSections);
    }
    
    public static MenuSection toSectionDomain(MenuSectionEntity entity, TenantId tenantId) {
        MenuSection section = new MenuSection(
            entity.id,
            tenantId,
            entity.name,
            entity.displayOrder
        );
        
        if (entity.items != null) {
            List<MenuItem> items = entity.items.stream()
                .map(item -> toItemDomain(item, tenantId))
                .collect(Collectors.toList());
            section.setItems(items);
        }
        
        return section;
    }
    
    public static MenuSection toSectionDomainWithoutItems(MenuSectionEntity entity) {
        return new MenuSection(
            entity.id,
            new TenantId(entity.restaurantId),
            entity.name,
            entity.displayOrder
        );
    }
    
    public static MenuItem toItemDomain(MenuItemEntity entity, TenantId tenantId) {
        Set<DietaryTag> tags = new HashSet<>();
        if (entity.dietaryTags != null) {
            tags = Arrays.stream(entity.dietaryTags)
                .map(DietaryTag::valueOf)
                .collect(Collectors.toSet());
        }
        
        return new MenuItem(
            entity.id,
            entity.sectionId,
            tenantId,
            entity.name,
            entity.description,
            entity.price,
            entity.imageUrl,
            entity.available,
            tags,
            entity.displayOrder
        );
    }
    
    public static MenuItem toItemDomainSimple(MenuItemEntity entity) {
        return toItemDomain(entity, new TenantId(entity.restaurantId));
    }
    
    public static MenuSectionEntity toSectionEntity(MenuSection domain) {
        MenuSectionEntity entity = new MenuSectionEntity();
        entity.id = domain.getId();
        entity.restaurantId = domain.getTenantId().value();
        entity.name = domain.getName();
        entity.displayOrder = domain.getDisplayOrder();
        return entity;
    }
    
    public static MenuItemEntity toItemEntity(MenuItem domain) {
        MenuItemEntity entity = new MenuItemEntity();
        entity.id = domain.getId();
        entity.sectionId = domain.getSectionId();
        entity.restaurantId = domain.getTenantId().value();
        entity.name = domain.getName();
        entity.description = domain.getDescription();
        entity.price = domain.getPrice();
        entity.imageUrl = domain.getImageUrl();
        entity.available = domain.isAvailable();
        entity.dietaryTags = domain.getDietaryTags().stream()
            .map(DietaryTag::name)
            .toArray(String[]::new);
        entity.displayOrder = domain.getDisplayOrder();
        return entity;
    }
    
    public static void updateSectionEntity(MenuSectionEntity entity, MenuSection domain) {
        entity.name = domain.getName();
        entity.displayOrder = domain.getDisplayOrder();
    }
    
    public static void updateItemEntity(MenuItemEntity entity, MenuItem domain) {
        entity.sectionId = domain.getSectionId();
        entity.name = domain.getName();
        entity.description = domain.getDescription();
        entity.price = domain.getPrice();
        entity.imageUrl = domain.getImageUrl();
        entity.available = domain.isAvailable();
        entity.dietaryTags = domain.getDietaryTags().stream()
            .map(DietaryTag::name)
            .toArray(String[]::new);
        entity.displayOrder = domain.getDisplayOrder();
    }
}
