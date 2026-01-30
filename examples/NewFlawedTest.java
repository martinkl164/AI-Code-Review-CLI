/**
 * New test file with security and quality flaws
 */
public class newFlawedTest {  // Naming: should be PascalCase
    
    // Security: Hardcoded secret
    private String SECRET_TOKEN = "ghp_xxxx1234567890abcdef";
    
    // Thread safety issue
    public static int sharedCounter = 0;
    
    public String getData(String user_input) {  // Naming: param should be camelCase
        // SQL injection
        String sql = "SELECT * FROM data WHERE id = " + user_input;
        
        // NPE risk - no null check
        return user_input.trim().toLowerCase();
    }
    
    // Naming: underscore in method name
    public void process_request() {
        sharedCounter++;  // Thread unsafe
        
        try {
            throw new Exception("test");
        } catch (Exception e) {
            // Empty catch - swallowing exception
        }
    }
}
