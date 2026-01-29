package com.example.badcode; // ISSUE: Package naming - should be lowercase

import java.util.*;
import java.io.*;

// ISSUE: Class name doesn't follow PascalCase (should be BadCodeExample)
public class badCodeExample {
    
    // ISSUE: Constant not following UPPER_SNAKE_CASE (should be MAX_COUNT)
    private static final int maxCount = 100;
    
    // ISSUE: Hardcoded secret (BLOCK)
    private static final String DB_PASSWORD = "admin123";
    private static final String API_KEY = "sk-1234567890abcdef";
    
    // ISSUE: Variable name doesn't follow camelCase (should be userName)
    private String UserName;
    
    // ISSUE: Variable name starts with underscore (not Java convention)
    private int _counter;
    
    // ISSUE: Variable name uses Hungarian notation (not Java convention)
    private String strName;
    
    // ISSUE: Thread safety (BLOCK)
    private static int counter = 0;
    
    // ISSUE: Method name doesn't follow camelCase (should be doSomething)
    public void DoSomething() {
        // ISSUE: Variable name doesn't follow camelCase (should be myVariable)
        int MyVariable = 5;
        
        // ISSUE: Variable name uses single letter (should be descriptive)
        int x = 10;
        int y = 20;
        
        // ISSUE: Magic number without constant
        if (x > 42) {
            System.out.println("Too large");
        }
    }
    
    // ISSUE: Method name uses underscore (should be getUserByName)
    public void get_user_by_name(String username) throws Exception {
        // ISSUE: SQL Injection vulnerability (BLOCK)
        String query = "SELECT * FROM users WHERE username = '" + username + "'";
        // This should use PreparedStatement!
    }
    
    // ISSUE: Method name doesn't follow camelCase (should be processUser)
    public String ProcessUser(User user) {
        // ISSUE: NullPointerException risk (BLOCK)
        return user.getName().toUpperCase(); // user could be null!
    }
    
    // ISSUE: Method name abbreviation unclear (should be calculateTotalPrice)
    public double calcTotal(double price, double tax) {
        // ISSUE: Magic numbers
        return price * 1.08 + tax * 1.05;
    }
    
    // ISSUE: Poor exception handling (WARN)
    public void readFile(String path) {
        try {
            // some file reading logic
        } catch (Exception e) {
            // Empty catch block - swallows exception!
        }
    }
    
    // ISSUE: Method name doesn't follow camelCase (should be incrementCounter)
    public void IncrementCounter() {
        counter++; // Not thread-safe!
    }
    
    // ISSUE: Method name uses wrong case (should be validateEmail)
    public boolean ValidateEmail(String email) {
        // ISSUE: Inefficient string comparison
        if (email == "") {
            return false;
        }
        return email.contains("@");
    }
    
    // ISSUE: Variable name doesn't follow camelCase (should be itemList)
    public void processItems(List<String> ItemList) {
        // ISSUE: Performance - inefficient collection usage (WARN)
        for (String item : ItemList) {
            if (item.equals("target")) {
                System.out.println("Found");
            }
        }
    }
    
    // ISSUE: Method name unclear abbreviation (should be getUserId)
    public int getUID() {
        return 123;
    }
    
    // ISSUE: Method name doesn't follow camelCase (should be isUserActive)
    public boolean IsUserActive(User u) {
        // ISSUE: Variable name single letter (should be user)
        return u != null;
    }
    
    // ISSUE: Method name uses underscore (should be saveUserData)
    public void save_user_data(String data) {
        // ISSUE: Unused variable
        String unusedVar = "test";
        
        // ISSUE: Dead code
        if (false) {
            System.out.println("Never executed");
        }
    }
    
    // ISSUE: Method name doesn't follow camelCase (should be deleteRecord)
    public void DeleteRecord(int id) {
        // ISSUE: Magic number
        if (id < 0 || id > 9999) {
            throw new IllegalArgumentException();
        }
    }
    
    // ISSUE: Variable name doesn't follow camelCase (should be result)
    public String GetResult() {
        String Result = "success";
        return Result;
    }
    
    // ISSUE: Method name unclear (should be convertToString)
    public String toString(Object obj) {
        // ISSUE: Shadowing Object.toString()
        return obj.toString();
    }
}

// ISSUE: Class name doesn't follow PascalCase (should be User)
class user {
    // ISSUE: Field name doesn't follow camelCase (should be name)
    private String Name;
    
    // ISSUE: Field name doesn't follow camelCase (should be email)
    private String Email;
    
    // ISSUE: Method name doesn't follow camelCase (should be getName)
    public String GetName() {
        return Name;
    }
    
    // ISSUE: Method name doesn't follow camelCase (should be setName)
    public void SetName(String name) {
        this.Name = name;
    }
    
    // ISSUE: Method name doesn't follow camelCase (should be getEmail)
    public String GetEmail() {
        return Email;
    }
}

// ISSUE: Class name uses underscore (should be DataProcessor)
class data_processor {
    // ISSUE: Method name doesn't follow camelCase (should be processData)
    public void Process_Data(String data) {
        // ISSUE: Variable name doesn't follow camelCase (should be processedData)
        String ProcessedData = data.toUpperCase();
        System.out.println(ProcessedData);
    }
}

// ISSUE: Interface name doesn't follow PascalCase (should be ServiceInterface)
interface service_interface {
    // ISSUE: Method name doesn't follow camelCase (should be execute)
    void Execute();
}

// ISSUE: Enum name doesn't follow PascalCase (should be Status)
enum status {
    // ISSUE: Enum constant doesn't follow UPPER_SNAKE_CASE (should be ACTIVE)
    active,
    inactive,
    pending
}
