public with sharing class ShipmentEventHandler {

    // Retry a transient failure up to this many times. Salesforce only allows a limited
    // number of retries before it stops the trigger's subscription, so stay well below it.
    @TestVisible
    private static final Integer MAX_RETRIES = 4;

    // Lab only: an event with this Location__c fails the first two attempts,
    // so the retry can be observed in the org and in tests.
    @TestVisible
    private static final String SIMULATE_FAILURE = 'SIMULATE_TRANSIENT_FAILURE';

    public static void handle(List<Shipment_Event__e> events) {
        Integer retries = EventBus.TriggerContext.currentContext().retries;
        System.debug('Shipment events: ' + events.size() + ', retry attempt: ' + retries);

        try {
            if (shouldSimulateFailure(events, retries)) {
                throw new TransientFailureException('Simulated transient failure');
            }
            updateShipments(events);
        } catch (Exception e) {
            if (isTransient(e) && retries < MAX_RETRIES) {
                // Salesforce redelivers the whole batch later; no new events are published
                throw new EventBus.RetryableException(
                    'Transient failure, retry ' + (retries + 1) + ' of ' + MAX_RETRIES + ': ' + e.getMessage());
            }
            // Permanent failure, or retries used up: don't block the subscription.
            // Week 13 writes these to Integration_Log__c instead of the debug log.
            System.debug(LoggingLevel.ERROR, 'Shipment events not processed: ' + e.getMessage());
        }
    }

    private static void updateShipments(List<Shipment_Event__e> events) {
        // 1. Collect tracking numbers
        Set<String> trackingNumbers = new Set<String>();
        for (Shipment_Event__e evt : events) {
            trackingNumbers.add(evt.Tracking_Number__c);
        }

        // 2. One query: find the Shipments
        Map<String, Shipment__c> byTracking = new Map<String, Shipment__c>();
        for (Shipment__c s : [SELECT Id, Tracking_Number__c, Status__c
                              FROM Shipment__c
                              WHERE Tracking_Number__c IN :trackingNumbers]) {
            byTracking.put(s.Tracking_Number__c, s);
        }

        // 3. Last event per Shipment wins (events arrive in publish order)
        Map<Id, Shipment__c> toUpdate = new Map<Id, Shipment__c>();
        for (Shipment_Event__e evt : events) {
            Shipment__c s = byTracking.get(evt.Tracking_Number__c);
            if (s == null) continue;   // unknown tracking number: log it in a later week
            toUpdate.put(s.Id, new Shipment__c(Id = s.Id, Status__c = evt.Status__c));
        }

        update toUpdate.values();      // no duplicate Ids, so no "duplicate id in list" error
    }

    private static Boolean shouldSimulateFailure(List<Shipment_Event__e> events, Integer retries) {
        if (retries >= 2) {
            return false;   // fail the first two attempts, then succeed
        }
        for (Shipment_Event__e evt : events) {
            if (evt.Location__c == SIMULATE_FAILURE) {
                return true;
            }
        }
        return false;
    }

    // Only failures that can succeed on a later attempt are worth retrying
    private static Boolean isTransient(Exception e) {
        if (e instanceof TransientFailureException) {
            return true;
        }
        if (e instanceof DmlException) {
            return ((DmlException) e).getDmlType(0) == StatusCode.UNABLE_TO_LOCK_ROW;
        }
        return false;
    }

    public class TransientFailureException extends Exception {}
}
