public class BadCodeExample {
    
    // ISSUE: Hardcoded secret (BLOCK)
    private static final String DB_PASSWORD = "admin123";
    private static final String API_KEY = "sk-1234567890abcdef";
    
    // ISSUE: SQL Injection vulnerability (BLOCK)
    public void getUserByName(String username) throws Exception {
        String query = "SELECT * FROM users WHERE username = '" + username + "'";
        // This should use PreparedStatement!
    }
    
    // ISSUE: NullPointerException risk (BLOCK)
    public String processUser(User user) {
        return user.getName().toUpperCase(); // user could be null!
    }
    
    // ISSUE: Poor exception handling (WARN)
    public void readFile(String path) {
        try {
            // some file reading logic
        } catch (Exception e) {
            // Empty catch block - swallows exception!
        }
    }
    
    // ISSUE: Thread safety (BLOCK)
    private static int counter = 0;
    public void incrementCounter() {
        counter++; // Not thread-safe!
    }
    
    // ISSUE: Naming convention violation (INFO)
    public void DoSomething() { // Should be doSomething()
        int MyVariable = 5; // Should be myVariable
    }
    
    // ISSUE: Performance - inefficient collection usage (WARN)
    public boolean containsItem(List<String> items, String target) {
        for (String item : items) {
            if (item.equals(target)) {
                return true;
            }
        }
        return false;
        // Should use Set or items.contains() for O(1) lookup
    }
}

// Helper class for the example
class User {
    private String name;
    
    public String getName() {
        return name;
    }
}
