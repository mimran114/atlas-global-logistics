trigger ShipmentEventTrigger on Shipment_Event__e (after insert) {
    ShipmentEventHandler.handle(Trigger.new);
}