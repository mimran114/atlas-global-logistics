# ADR 0001: Shipment status updates at 5M events/day

- **Status:** Accepted
- **Date:** 2026-11-08
- **Deciders:** Muhammad Imran (solution architect)
- **References:** [Event-Driven Architecture decision guide](https://architect.salesforce.com/docs/architect/decision-guides/guide/event-driven) · [Record-Triggered Automation decision guide](https://architect.salesforce.com/docs/architect/decision-guides/guide/record-triggered) · [Order of Execution lab](../platform/order-of-execution-lab.md)

## Context

Atlas Global Logistics runs a legacy shipment-tracking system that produces about **5 million status events a day**. Salesforce holds the `Shipment__c` record that service agents, partners and customers look at, so its `Status__c` must follow the tracking system closely.

| Measure | Value |
|---|---|
| Daily events | ~5,000,000 |
| Average rate | ~58 events/second |
| Peak (3× average, e.g. peak season, Monday mornings) | ~175 events/second |
| Freshness needed | Minutes, not hours: agents answer "where is my shipment?" calls from this status |
| Direction | **Inbound**: tracking system → Salesforce |

The decision guide asks whether there is a **genuine business need** for an event-driven architecture. Three of the guide's scenarios apply:

- **High-volume writes:** millions of updates a day, with surges.
- **High-volume reads:** at peak, events can arrive faster than Salesforce can process them, so they need buffering.
- **Near real-time notifications:** status changes must reach users and, later, other systems (SAP, data warehouse, customer portal) quickly.

The scenarios where the guide says EDA does **not** fit don't apply: no user waits for a response, and the data changes constantly rather than rarely.

## Decision

1. **The tracking system publishes a `Shipment_Event__e` platform event** (high volume, *Publish After Commit*) for each status change.
   - **Interface:** the **Pub/Sub API** (gRPC), which the guide recommends for new publish/subscribe integrations.
   - **Legacy fallback:** if the tracking system can't use gRPC, it publishes through the **REST API** (`POST /services/data/vXX.X/sobjects/Shipment_Event__e/`) or through middleware such as MuleSoft.
2. **The event carries the business key, not a Salesforce Id.** Fields: `Tracking_Number__c` (matches the External ID on `Shipment__c`), `Status__c`, `Event_Time__c`, `Location__c`. External systems don't know Salesforce record Ids.
3. **An Apex subscriber trigger (`ShipmentEventTrigger` → `ShipmentEventHandler`) updates `Shipment__c.Status__c`.**
   - It collects the tracking numbers, runs **one query**, and builds a **`Map<Id, Shipment__c>` keyed by Shipment Id**, so several events for the same shipment in one batch become a single update and **the last event wins** (events in a batch arrive in publish order). This also avoids the "duplicate id in list" error.
   - Unknown tracking numbers are skipped, not failed.
4. **`Shipment_Event__e` is inbound only.** The subscriber never publishes `Shipment_Event__e`. Any outbound notification (e.g. to SAP) will use a separate event, so the subscriber can't trigger itself in a loop.

## Alternatives considered

| Option | Why rejected |
|---|---|
| **Direct REST record updates** (tracking system updates `Shipment__c` via REST/Composite API) | 5M calls a day would consume API allocations, and every call competes for record locks during surges. No buffering: the tracking system would have to slow down or retry when Salesforce is busy. |
| **Nightly batch file** (Bulk API) | Simple and cheap, but status would be up to a day old. Fails the freshness requirement. The guide recommends batch only when data changes infrequently. |
| **Change Data Capture** | CDC publishes changes *from* Salesforce records. Here the changes originate outside Salesforce, so it doesn't fit this inbound flow. |
| **Middleware queue with point-to-point calls** | Possible later for fanout to many consumers, but adds a platform Atlas doesn't need for a single inbound subscriber today. |

## Consequences

**Positive**
- The event bus absorbs **spikes**: the tracking system publishes and moves on, and the subscriber processes events in batches at its own pace.
- The tracking system is **decoupled** from Salesforce internals: it only needs the event's contract, not object structures or record Ids.
- New consumers can subscribe later without changing the tracking system.

**Negative and risks, with mitigations**

| Risk | Mitigation |
|---|---|
| **Transient failures** (e.g. record locks, or a downstream step failing) | The subscriber throws `EventBus.RetryableException`, so Salesforce **redelivers the batch** without new events being published. Use `setResumeCheckpoint(replayId)` so events already processed aren't repeated. Retries are limited: after repeated failures the trigger's subscription stops and must be monitored and resumed. *(Planned; not in the week 3 skeleton.)* |
| **Retention:** events are kept for 3 days | An outage longer than 3 days means replaying from the tracking system. Monitor the subscription so outages are caught early. |
| **Invalid status values** (`Status__c` on the event is text; on `Shipment__c` it's a restricted picklist) | One invalid value fails the whole `update`. Validate values against the picklist before updating, or use `Database.update(records, false)` and log the failures. *(Planned.)* |
| **Out-of-order events across batches** | Within a batch, the last event wins. Across batches, compare `Event_Time__c` with the last applied event time and ignore older events. *(Planned.)* |
| **Every status update runs the full Shipment save** (flows, trigger, validation and duplicate rules) | The week 2 lab measured the duplicate rule at **76–91 ms per record** on a single save. At 175 events/second this is significant. Make `Tracking_Number__c` a unique field (week 7) and review whether the duplicate rule should run on edit for this path. Shipment is heading for **high automation density**, so consolidate into a trigger framework (week 22). |
| **Event allocations** | 5M events a day must fit the org's platform event publishing and delivery allocations. Confirm the org's allocation and, if needed, the add-on before go-live. |
| **Message structure changes** | Treat the event fields as a contract with the tracking system. Version the event (e.g. `Shipment_Event_v2__e`) with a clear lifecycle rather than changing fields in place. |

## Follow-ups

- Week 7: make `Tracking_Number__c` unique (upsert key and duplicate protection).
- Week 11: inbound REST API (`/atlas/shipments`) publishes `Shipment_Event__e` (legacy fallback path).
- Outbound integrations (e.g. SAP) use a separate event or a Queueable, never this subscriber.
- Week 22: trigger framework for Shipment; add retry, checkpoint and out-of-order handling.
