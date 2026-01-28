public class TestCodeReview {
    // ISSUE: Hardcoded secret
    private static final String API_KEY = "sk-test-12345";
    
    // ISSUE: SQL Injection
    public void getUser(String username) {
        String query = "SELECT * FROM users WHERE name = '" + username + "'";
    }
}
