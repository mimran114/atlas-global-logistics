public with sharing class ShipmentTriggerHandler {
    private static Set<Id> processedAfter = new Set<Id>();

    public static void beforeSave(List<Shipment__c> records) {
        for (Shipment__c s : records) {
            if (String.isBlank(s.Tracking_Number__c)) {
                s.Tracking_Number__c = 'ATL-' + String.valueOf(Crypto.getRandomInteger()).replace('-', '').left(10);
            }
            s.Automation_Trace__c = (s.Automation_Trace__c == null ? '' : s.Automation_Trace__c)
                + '2-BeforeTrigger(band=' + s.Weight_Band__c + '); ';
        }
    }

    public static void afterSave(List<Shipment__c> records, Map<Id, Shipment__c> oldMap) {
        System.debug('5-AfterTrigger, records in chunk: ' + records.size());
        List<Task> tasks = new List<Task>();
        for (Shipment__c s : records) {
            if (processedAfter.contains(s.Id)) continue;
            processedAfter.add(s.Id);
            Shipment__c old = oldMap == null ? null : oldMap.get(s.Id);
             System.debug('old map in insertt: ' + old);
            if (s.Status__c == 'Exception' && (old == null || old.Status__c != 'Exception')) {
                tasks.add(new Task(WhatId = s.Id, Subject = 'Investigate shipment exception'));
            }
        }
        if (!tasks.isEmpty()) insert tasks;
    }
}