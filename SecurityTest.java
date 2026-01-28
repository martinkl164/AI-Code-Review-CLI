public class SecurityTest {
    // Hardcoded API key - should be flagged as BLOCK
    private static final String API_KEY = "sk-prod-1234567890";
    
    // SQL injection vulnerability - should be flagged as BLOCK
    public void findUser(String username) {
        String sql = "SELECT * FROM users WHERE username = '" + username + "'";
        // Missing PreparedStatement
    }
    
    // NullPointerException risk - should be flagged as BLOCK
    public String processData(User user) {
        return user.getName().toUpperCase(); // user could be null
    }
}

class User {
    private String name;
    public String getName() { return name; }
}
