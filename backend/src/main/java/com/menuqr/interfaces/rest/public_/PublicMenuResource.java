package com.menuqr.interfaces.rest.public_;

import com.menuqr.application.menu.GetPublicMenuUseCase;
import com.menuqr.application.menu.dto.MenuDTOs.*;
import com.menuqr.domain.menu.Menu;
import com.menuqr.domain.menu.MenuItem;
import com.menuqr.domain.menu.MenuSection;
import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.parameters.Parameter;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

@Path("/api/menu")
@Produces(MediaType.APPLICATION_JSON)
@Tag(name = "Public Menu", description = "Public endpoints for viewing menus (no auth required)")
public class PublicMenuResource {
    
    @Inject
    GetPublicMenuUseCase getPublicMenuUseCase;
    
    @GET
    @Path("/{slug}")
    @Operation(summary = "Get public menu", description = "Returns the menu for a restaurant by slug. Only shows available items.")
    @APIResponse(responseCode = "200", description = "Menu found")
    @APIResponse(responseCode = "404", description = "Menu not found")
    public Response getMenu(@Parameter(description = "Restaurant URL slug") @PathParam("slug") String slug) {
        return getPublicMenuUseCase.execute(slug)
            .map(this::toMenuResponse)
            .map(Response::ok)
            .map(Response.ResponseBuilder::build)
            .orElseGet(() -> Response.status(Response.Status.NOT_FOUND)
                .entity(new ErrorResponse("NOT_FOUND", "Menu not found"))
                .build());
    }
    
    @Inject
    com.menuqr.application.menu.RecommendMenuItemsUseCase recommendMenuItemsUseCase;

    @POST
    @Path("/{slug}/recommendations")
    @Operation(summary = "Get recommendations", description = "Sugerencias de ítems del menú (aleatorio entre disponibles fuera del carrito).")
    public Response getRecommendations(@PathParam("slug") String slug, RecommendationRequestBody body) {
        if (body == null) {
            body = new RecommendationRequestBody();
        }
        var recommended = recommendMenuItemsUseCase.execute(
            slug,
            body.items_in_cart,
            body.menu_item_ids
        );
        return Response.ok(new RecommendationResponseBody(recommended)).build();
    }
    
    private MenuResponse toMenuResponse(Menu menu) {
        return new MenuResponse(
            menu.getTenantId() != null ? menu.getTenantId().toString() : null,
            menu.getRestaurantName(),
            menu.getSlug(),
            menu.getSortedSections().stream()
                .map(this::toSectionResponse)
                .toList()
        );
    }
    
    private SectionResponse toSectionResponse(MenuSection section) {
        return new SectionResponse(
            section.getId().toString(),
            section.getName(),
            section.getDisplayOrder(),
            section.getItems().stream()
                .map(this::toItemResponse)
                .toList()
        );
    }
    
    private ItemResponse toItemResponse(MenuItem item) {
        return new ItemResponse(
            item.getId().toString(),
            item.getSectionId().toString(),
            item.getName(),
            item.getDescription(),
            item.getPrice().toPlainString(),
            item.getImageUrl(),
            item.isAvailable(),
            item.getDietaryTags(),
            item.getDisplayOrder()
        );
    }
    
    public record ErrorResponse(String code, String message) {}
}
