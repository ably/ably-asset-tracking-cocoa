//
//  File.swift
//  
//
//  Created by Łukasz Szyszkowski on 27/08/2021.
//

import Foundation
import XCTest

class WaitAsync {
    
    enum ResultError: Error {
        case timeout
    }
    
    private let queue = DispatchQueue(label: "com.abl.tests.wait-async")
    
    func wait(_ description: String, condition: @escaping () -> (Bool)) {
        let expectation = XCTestExpectation(description: description)
        var loopBreak = false
        queue.async {            
            while true {
                if loopBreak { break }
                
                if condition() {
                    expectation.fulfill()
                    break
                }
                
                CFRunLoopRunInMode(CFRunLoopMode.defaultMode, CFTimeInterval(0.1), false)
            }
        }
        
        let result = XCTWaiter.wait(for: [expectation], timeout: 10.0)
        
        switch result {
        case .timedOut:
            XCTFail("\(description) - Timeout!")
        default: ()
        }
        
        loopBreak = true
    }
}
