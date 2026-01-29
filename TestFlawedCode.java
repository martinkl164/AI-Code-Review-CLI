package com.example.test;

import java.sql.*;

// ISSUE: Class name doesn't follow PascalCase
public class testFlawedCode {
    
    // ISSUE: Hardcoded secret (BLOCK severity)
    private static final String DB_PASSWORD = "super_secret_password_123";
    private static final String API_KEY = "sk-abcdefghijklmnopqrstuvwxyz";
    
    // ISSUE: Variable name doesn't follow camelCase
    private String UserName;
    
    // ISSUE: Thread safety issue (BLOCK severity)
    private static int globalCounter = 0;
    
    // ISSUE: Method name doesn't follow camelCase
    public void ProcessUser(String username) {
        // ISSUE: SQL Injection vulnerability (BLOCK severity)
        String query = "SELECT * FROM users WHERE username = '" + username + "'";
        // Should use PreparedStatement!
    }
    
    // ISSUE: NullPointerException risk (BLOCK severity)
    public String getUserName(User user) {
        return user.getName().toUpperCase(); // user could be null!
    }
    
    // ISSUE: Empty catch block (WARN severity)
    public void readFile(String path) {
        try {
            // file reading logic
        } catch (Exception e) {
            // Empty catch - swallows exception!
        }
    }
    
    // ISSUE: Method name uses underscore
    public void save_user_data(String data) {
        // ISSUE: Variable name doesn't follow camelCase
        String ProcessedData = data.toUpperCase();
        System.out.println(ProcessedData);
    }
    
    // ISSUE: Inefficient string comparison
    public boolean validateEmail(String email) {
        if (email == "") { // Should use .isEmpty()
            return false;
        }
        return email.contains("@");
    }
}

// ISSUE: Class name doesn't follow PascalCase
class user {
    // ISSUE: Field name doesn't follow camelCase
    private String Name;
    
    // ISSUE: Method name doesn't follow camelCase
    public String GetName() {
        return Name;
    }
}
