public with sharing class ShipmentEventHandler {
    public static void handle(List<Shipment_Event__e> events) {
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
}