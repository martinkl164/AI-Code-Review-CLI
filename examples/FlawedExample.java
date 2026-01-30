/**
 * Test file with intentional flaws for AI code review testing
 */
public class flawedExample {  // Wrong: should be PascalCase
    
    // Security: Hardcoded credentials
    private static String DB_PASSWORD = "admin123";
    private static String api_key = "sk-secret-key-12345";
    
    // Naming: Wrong case
    private String UserName;
    private int total_count;
    
    // Thread safety: Mutable static without synchronization
    public static int counter = 0;
    
    public void ProcessData(String Input) {  // Wrong: method/param should be camelCase
        // SQL Injection vulnerability
        String query = "SELECT * FROM users WHERE name = '" + Input + "'";
        
        // NullPointerException risk
        String result = Input.toUpperCase();
        
        // Empty catch block
        try {
            int value = Integer.parseInt(Input);
        } catch (Exception e) {
            // bad: swallowing exception
        }
        
        // Inefficient string comparison
        if (Input == "") {
            System.out.println("Empty");
        }
        
        counter++;  // Thread unsafe increment
    }
    
    // Wrong naming: underscore in method
    public void save_to_database() {
        System.out.println("Saving with password: " + DB_PASSWORD);
    }
}
