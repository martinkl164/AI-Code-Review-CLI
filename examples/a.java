package com.example.badcode; // ISSUE: Package naming - should be lowercase

// Test file for WSL 2 auto-delegation
import java.util.*;
import java.io.*;

// ISSUE: Class name doesn't follow PascalCase (should be BadCodeExample)
public class badCodeExample {
    
    // ISSUE: Constant not following UPPER_SNAKE_CASE (should be MAX_COUNT)
    private static final int maxCount = 100;    
 
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
}
