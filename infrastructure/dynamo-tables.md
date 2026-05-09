# DynamoDB Table Design

## Table: menuqr-events
Billing: PAY_PER_REQUEST (on-demand)

### Keys
| Key  | Type   | Pattern                          |
|------|--------|----------------------------------|
| PK   | String | TENANT#{tenantId}                |
| SK   | String | `EVENT#{iso_timestamp}#{uuid}` (ver nota abajo) |

Misma fecha/hora en **tres sitios**: el `{iso_timestamp}` de la `SK`, el atributo `timestamp` y la parte tras `#` en `eventTypeTimestamp` son el **mismo** valor ISO-8601 del instante del evento (en Quarkus/Java: `Instant.toString()`).

### LSI (local secondary index)
| Index          | Partition key | Sort key             | Use case                         |
|----------------|---------------|----------------------|----------------------------------|
| LSI-EventType  | `PK` (igual que la tabla) | `eventTypeTimestamp` | Filtrar por tipo de evento + tiempo en un tenant |

**Restricciones LSI:** solo se define **al crear la tabla**. Límite **10 GB** por valor de `PK` entre tabla base y LSIs. Las queries al LSI usan permisos sobre la **tabla base**.

### Item attributes
- `PK` (String): Partition key
- `SK` (String): Sort key
- `tenantId` (String): Restaurant tenant ID (atributo de datos; queries por tenant usan `PK`)
- `eventType` (String): MENU_VIEW, ITEM_VIEW, SECTION_VIEW, FILTER_USED
- `eventTypeTimestamp` (String): `{eventType}#{iso_timestamp}` — mismo `{iso_timestamp}` que en `SK` y `timestamp`; sort key del LSI `LSI-EventType`
- `itemId` (String, optional): Menu item ID for ITEM_VIEW events
- `sectionId` (String, optional): Menu section ID for SECTION_VIEW events
- `sessionId` (String): Anonymous session identifier
- `timestamp` (String): instante del evento en ISO-8601 (idéntico al fragmento temporal embebido en `SK` y en `eventTypeTimestamp`)
- `metadata` (Map, optional): Additional context (e.g., filter name)

### Example item
```json
{
  "PK": "TENANT#550e8400-e29b-41d4-a716-446655440000",
  "SK": "EVENT#2024-03-15T13:45:22.123Z#7c9e6679-7425",
  "tenantId": "550e8400-e29b-41d4-a716-446655440000",
  "eventType": "ITEM_VIEW",
  "eventTypeTimestamp": "ITEM_VIEW#2024-03-15T13:45:22.123Z",
  "itemId": "a3bb189e-8bf9-3888-9912-ace4e6543002",
  "sessionId": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "timestamp": "2024-03-15T13:45:22.123Z",
  "metadata": {}
}
```

### Query examples

**All events for tenant in last 30 days:**
```
KeyConditionExpression: PK = :pk AND SK BETWEEN :from AND :to
:pk = "TENANT#abc"
:from = "EVENT#2024-02-14"
:to = "EVENT#2024-03-16"
```

**Events of one type for tenant in a time range (LSI):**
```
Index: LSI-EventType
KeyConditionExpression: PK = :pk AND eventTypeTimestamp BETWEEN :etFrom AND :etTo
:pk = "TENANT#<uuid>"
```

**Por plato (sin GSI):** filtrar en aplicación los `ITEM_VIEW` devueltos por query a tabla base o LSI, o agregar por `itemId` en memoria (como hace el dashboard).

### Access Patterns

1. **Dashboard analytics**: Query by tenant + time range on base table, aggregate in application
2. **Realtime stats**: Query last 60 minutes for a tenant (base table)
3. **By event type + period**: Query `LSI-EventType` with `PK` + `eventTypeTimestamp` range
4. **Item popularity**: Filtrar `ITEM_VIEW` sobre el resultado de la query por tenant + periodo (tabla base)
5. **Filter usage**: Query `FILTER_USED` via LSI or base + filter, group by `metadata.filter`

### Capacity Planning

For a restaurant with:
- 1,000 menu views/day
- 3,000 item views/day (avg 3 items viewed per menu view)
- 500 section views/day
- 100 filter uses/day

**Daily writes**: ~4,600 items
**Monthly writes**: ~140,000 items
**30-day storage**: ~50 MB (assuming ~350 bytes per item)

On-demand pricing estimate: ~$0.50/month for this volume
