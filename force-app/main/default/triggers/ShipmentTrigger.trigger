trigger ShipmentTrigger on Shipment__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        ShipmentTriggerHandler.beforeSave(Trigger.new);
    } else {
        ShipmentTriggerHandler.afterSave(Trigger.new, Trigger.oldMap);
    }
}