public class BadSecurityCode {
    // CRITICAL: Hardcoded API credentials
    private static final String API_KEY = "sk-live-123456789";
    private static final String DB_PASSWORD = "SuperSecret123!";
    
    // CRITICAL: SQL Injection vulnerability
    public void deleteUser(String userId) {
        String sql = "DELETE FROM users WHERE id = '" + userId + "'";
        executeQuery(sql);
    }
    
    // CRITICAL: NullPointerException risk
    public int calculateTotal(Order order) {
        return order.getItems().size() * order.getPrice(); // order can be null!
    }
    
    private void executeQuery(String sql) {
        // dummy method
    }
}

class Order {
    private java.util.List<String> items;
    private int price;
    public java.util.List<String> getItems() { return items; }
    public int getPrice() { return price; }
}
