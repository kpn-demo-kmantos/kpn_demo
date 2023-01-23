@isTest
public class OrderControllerTest {
    @TestSetup
    static void makeData() {
        // Create our Data, of course as a best practice we can create a Data Dummy Factory for our Test classes that can be also reusable.
        Account account1 = new Account(Name = 'Test Account 1', AccountNumber = 'KPN0001');
        insert account1;
        Product2 product1 = new Product2(Name = 'Test Product 1', ProductCode = 'KPN0001');
        insert product1;
        Product2 product2 = new Product2(Name = 'Test Product 2', ProductCode = 'KPN0002');
        insert product2;
        Pricebook2 pricebook1 = new Pricebook2(Name = 'Standard Price Book');
        insert pricebook1;
        Order order1 = new Order(Pricebook2Id = pricebook1.Id, EffectiveDate = Date.today(), AccountId = account1.Id, Type = 'Purchase', Status = 'Draft');
        insert order1;
        PricebookEntry pricebookEntry1 = new PricebookEntry(Product2Id = product1.Id, UnitPrice = 101, Pricebook2Id = Test.getStandardPricebookId(), IsActive = true);
        insert pricebookEntry1;
        PricebookEntry pricebookEntry2 = new PricebookEntry(Product2Id = product1.Id, UnitPrice = 100, Pricebook2Id = pricebook1.Id, IsActive = true);
        insert pricebookEntry2;
        PricebookEntry pricebookEntry3 = new PricebookEntry(Product2Id = product2.Id, UnitPrice = 101, Pricebook2Id = Test.getStandardPricebookId(), IsActive = true);
        insert pricebookEntry3;
        PricebookEntry pricebookEntry4 = new PricebookEntry(Product2Id = product2.Id, UnitPrice = 100, Pricebook2Id = pricebook1.Id, IsActive = true);
        insert pricebookEntry4;
        OrderItem orderItem1 = new OrderItem(Quantity = 1, OrderId = order1.Id, Product2Id = product1.Id, PricebookEntryId = pricebookEntry2.Id, UnitPrice = 100);
        insert orderItem1;
    }

    @isTest
    public static void testGetAvailableProducts() {
        List<PricebookEntry> pbes = OrderController.getAvailableProducts();
        System.assertEquals(2, pbes.size(), 'Expected 2 PricebookEntry');
    }

    @isTest
    public static void testGetOrderProducts() {
        Order order = [SELECT Id FROM Order LIMIT 1];
        List<OrderItem> orderItems = OrderController.getOrderProducts(order.Id);
        System.assertEquals(1, orderItems.size(), 'Expected 1 OrderItem');
    }

    @isTest
    public static void testAddToOrder() {
        Order order = [SELECT Id FROM Order LIMIT 1];
        List<PricebookEntry> pbes = [SELECT Id, UnitPrice FROM PricebookEntry WHERE UnitPrice = 100];
        Boolean success = OrderController.addToOrder(pbes, order.Id);
        System.assertEquals(true, success, 'Expected success');
    }

    @isTest
    public static void testConfirmOrder() {
        Order order = [SELECT Id FROM Order LIMIT 1];
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MockTest());
        Boolean success = OrderController.confirmOrder(order.Id);
        Test.stopTest();
        System.assertEquals(true, success, 'Expected success');
    }
}
