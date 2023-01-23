/**
 *  @author         Konstantinos Mantos
 *  @date           23 Jan 2023
 *  @description    Controller of Order lifecycle
 */
public with sharing class OrderController {
    /**
    * @description  This method returns all available products that have a pricebook entry and are active and belong to the standard pricebook, as a best practice I limit our results and enforce security, also I order by price so they appear from cheaper to most expensive.
    * @return       List<PricebookEntry>    Returns the list of Pricebook Entries to display in the first LWC.
    */
    @AuraEnabled(cacheable=true)
    public static List<PricebookEntry> getAvailableProducts() {
        return [
            SELECT Id, Name, UnitPrice
            FROM PricebookEntry
            WHERE IsActive = true AND Pricebook2.Name = 'Standard Price Book'
            WITH SECURITY_ENFORCED
            ORDER BY UnitPrice ASC
            LIMIT 50000
        ];
    }

    /**
    * @description  This method returns all selected Order products of an Order, as a best practice I limit our results and enforce security, also I order by price so they appear from cheaper to most expensive.
    * @param        recordId            The Order Id.
    * @return       List<OrderItem>     Returns the list of Order Items to display in the second LWC.
    */
    @AuraEnabled
    public static List<OrderItem> getOrderProducts(String recordId) {
        return [
            SELECT Id, Product2.Name, UnitPrice, Quantity, TotalPrice
            FROM OrderItem
            WHERE OrderId = :recordId
            WITH SECURITY_ENFORCED
            ORDER BY UnitPrice ASC
            LIMIT 50000
        ];
    }

    /**
    * @description  This method tries to add a list of products to the order.
    * @param        selectedProducts    List of selected Products to be added to the Order.
    * @param        orderId             The Order Id.
    * @return       Boolean             Returns true if successfully added to order otherwise false.
    */
    @AuraEnabled
    public static Boolean addToOrder(List<PricebookEntry> selectedProducts, String orderId) {
        try {
            Pricebook2 pricebook = [SELECT Id FROM Pricebook2 WHERE Name = 'Standard Price Book' WITH SECURITY_ENFORCED LIMIT 1];
            Order order = [SELECT Id, Pricebook2Id FROM Order WHERE Id = :orderId WITH SECURITY_ENFORCED LIMIT 1];
            // Our Order must have a Pricebook assigned to it otherwise it will fail adding products to it (That's a out-of-the-box Salesforce restriction regarding Order  standard object).
            if (order.Pricebook2Id != pricebook.Id) {
                order.Pricebook2Id = pricebook.Id;
                // As a best practice always check if you have access to do a dml otherwise if more time was available we could make a error handler.
                if (Schema.sObjectType.Order.isUpdateable()) {
                    update order;
                }
            }

            List<OrderItem> existingOrderItems = [SELECT Id, PricebookEntryId, Quantity FROM OrderItem WHERE OrderId = :order.Id WITH SECURITY_ENFORCED];
            Map<String, OrderItem> pricebookEntries = new Map<String, OrderItem>();
            // Get existing order Items and make a Map by PricebookEntry instead of OrderItem so that we can later update the Quantity of the OrderItem easier.
            for (OrderItem orderItem : existingOrderItems) {
                pricebookEntries.put(orderItem.PricebookEntryId, orderItem);
            }
            List<OrderItem> orderItems = new List<OrderItem>();
            for (PricebookEntry pbe : selectedProducts) {
                // Product was already in the Order so just increment the Quantity.
                if (pricebookEntries.containsKey(pbe.Id)) {
                    pricebookEntries.get(pbe.Id).Quantity += 1;
                } else {
                    // Create an Order Item because the product wasn't in the Order.
                    OrderItem orderItem = new OrderItem();
                    orderItem.OrderId = order.Id;
                    orderItem.PricebookEntryId = pbe.Id;
                    orderItem.UnitPrice = pbe.UnitPrice;
                    orderItem.Quantity = 1;
                    orderItems.add(orderItem);
                }
            }
            // As a best practice always do dml & soqls outside for-loops and check for CRUD permissions.
            if (Schema.sObjectType.OrderItem.isCreateable()) {
                insert orderItems;
            }
            if (Schema.sObjectType.OrderItem.isUpdateable()) {
                update pricebookEntries.values();
            }

            return true;
        } catch (Exception e) {
            // If any error occurs return false, if I had more time I could make an Error handler class that holds the error messages and is reusable.
            return false;
        }
    }

    /**
    * @description  This method tries to confirm the Order using an external dummy system.
    * @param        orderId             The Order Id.
    * @return       Boolean             Returns true if successfully confirmed order otherwise false.
    */
    @AuraEnabled
    public static Boolean confirmOrder(String orderId) {
        try {
            Order order = [SELECT Id, OrderNumber, Type, Status, Account.AccountNumber FROM Order WHERE Id = :orderId WITH SECURITY_ENFORCED LIMIT 1];
            List<OrderItem> orderItems = [SELECT Id, Product2.Name, Product2.ProductCode, UnitPrice, Quantity FROM OrderItem WHERE OrderId = :orderId];

            // Of course here we could make a Rest Controller that handles our API calls but for purposes of the Demo we just do it inside the method here.
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            // Since this is dummy its fine, but for serious projects we could always use Named Credentials to keep our endpoints & access credentials.
            request.setEndpoint('https://kpn-demo.requestcatcher.com');
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');

            // Thats the body of the Rest Api call that we will do. Since the exercise demanded a specific way of JSON structure I created a Wrapper that will produce our final JSON in the correct structure.
            OrderPayloadWrapper payload = new OrderPayloadWrapper();
            payload.accountNumber = order.Account.AccountNumber;
            payload.orderNumber = order.OrderNumber;
            payload.type = order.Type;
            payload.status = order.Status;
            List<OrderProductsWrapper> orderProductsPayload = new List<OrderProductsWrapper>();
            for (OrderItem orderItem : orderItems) {
                OrderProductsWrapper orderProduct = new OrderProductsWrapper();
                orderProduct.name = orderItem.Product2.Name;
                orderProduct.code = orderItem.Product2.ProductCode;
                orderProduct.unitPrice = orderItem.UnitPrice;
                orderProduct.quantity = Integer.valueOf(orderItem.Quantity);
                orderProductsPayload.add(orderProduct);
            }
            payload.orderProducts = orderProductsPayload;

            // Our JSON body is ready in the correct format with correct data types.
            request.setBody(JSON.serialize(payload));
            HttpResponse response = http.send(request);
            // After sending the response we can do a ton of things to better handle this using extensive error handling for each error code, but for purposes of the exercise we assume only 200 is good and all others fail.
            if(response.getStatusCode() == 200) {
                if (Schema.sObjectType.Order.isUpdateable()) {
                    // Update the order status to Activated which will make our 2 components to freeze and not be able to add new products or re-confirm the order for a second time.
                    order.Status = 'Activated';
                    update order;
                }
                return true;
            } else {
                return false;
            }
        } catch (Exception e) {
            // If any error occurs return false, if I had more time I could make an Error handler class that holds the error messages and is reusable.
            return false;
        }
    }

    // The Payload Wrapper
    public class OrderPayloadWrapper {
        public String accountNumber {get;set;}
        public String orderNumber {get;set;}
        public String type {get;set;}
        public String status {get;set;}
        public List<OrderProductsWrapper> orderProducts {get;set;}
    }

    // The Payload's Product Wrapper
    public class OrderProductsWrapper {
        public String name {get;set;}
        public String code {get;set;}
        public Decimal unitPrice {get;set;}
        public Integer quantity {get;set;}
    }
}