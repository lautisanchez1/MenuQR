package com.menuqr.application.menu;

import com.menuqr.infrastructure.ml.RecommendationModelLoader;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.jboss.logging.Logger;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Recomendaciones demo: hasta 3 ítems al azar del menú que no estén en el carrito.
 * Si hay artefacto en S3 ({@link RecommendationModelLoader}), ya está en memoria para sustituir esto por inferencia real.
 */
@ApplicationScoped
public class RecommendMenuItemsUseCase {

    private static final Logger LOG = Logger.getLogger(RecommendMenuItemsUseCase.class);

    @Inject
    GetPublicMenuUseCase getPublicMenuUseCase;

    @Inject
    RecommendationModelLoader recommendationModelLoader;

    public List<String> execute(String slug, List<String> itemsInCart, List<String> menuItemIdsFromClient) {
        if (recommendationModelLoader.isLoaded()) {
            LOG.tracef("Using mock recommendations; model artifact present (%d bytes)", recommendationModelLoader.byteSize());
        }
        List<String> candidates = resolveCandidates(slug, menuItemIdsFromClient);
        Set<String> cart = new HashSet<>();
        if (itemsInCart != null) {
            itemsInCart.stream().filter(id -> id != null && !id.isBlank()).forEach(cart::add);
        }
        List<String> pool = candidates.stream()
            .filter(id -> id != null && !id.isBlank() && !cart.contains(id))
            .toList();
        if (pool.isEmpty()) {
            return List.of();
        }
        int k = Math.min(3, pool.size());
        List<String> shuffled = new ArrayList<>(pool);
        Collections.shuffle(shuffled, ThreadLocalRandom.current());
        return shuffled.subList(0, k);
    }

    private List<String> resolveCandidates(String slug, List<String> menuItemIdsFromClient) {
        if (menuItemIdsFromClient != null && !menuItemIdsFromClient.isEmpty()) {
            return List.copyOf(menuItemIdsFromClient);
        }
        return getPublicMenuUseCase.execute(slug)
            .map(menu -> menu.getSortedSections().stream()
                .flatMap(s -> s.getItems().stream())
                .map(item -> item.getId().toString())
                .toList())
            .orElse(List.of());
    }
}
