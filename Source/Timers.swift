//
//  Timers.swift
//  JavaScriptCoreBrowserObjectModel
//
//  Created by Connor Grady on 10/7/17.
//  Copyright © 2017 Connor Grady. All rights reserved.
//

import Foundation
import JavaScriptCore

//@objc protocol TimerJSExport : JSExport {
//    func setTimeout(_ callback: JSValue, _ ms: Double) -> String
//    func clearTimeout(_ identifier: String)
//    func setInterval(_ callback: JSValue, _ ms: Double) -> String
//    func clearInterval(_ identifier: String)
//}

@objc open class Timers: NSObject {
    
    weak var jsQueue: DispatchQueue?
    weak var workerQueue: DispatchQueue?
    //
    // General
    //
    public override init() {
        super.init()
        setTimeout = { (callback, delay) in
            return self.createTimer(callback: callback, delay: delay, repeats: false)
        }
        clearTimeout = { (identifier) in
            self.invalidateTimer(identifier)
        }
        
        // Interval
        setInterval = { (callback, delay) in
            return self.createTimer(callback: callback, delay: delay, repeats: true)
        }
       clearInterval = { (identifier) in
            self.invalidateTimer(identifier)
        }
    }
    
    //public class var count: Int { return timers.count }
    
    //public class func destroy() {
    //    // TODO: iterate all `timers` & invalidate each
    //}
    
    // @usage:
    //   let context = JSContext()!
    //   Timers.extend(context)
    //   context.evaluateScript("setTimeout(done, 5 * 1000)") // `done()` is called after 5s
    open func extend(
        _ jsContext: JSContext,
        managerQueue: DispatchQueue,
        jsQueue: DispatchQueue
    ) {
        workerQueue = managerQueue
        self.jsQueue = jsQueue
        
        jsQueue.async {
            jsContext.setObject(self.setTimeout, forKeyedSubscript: "setTimeout" as (NSCopying & NSObjectProtocol))
            jsContext.setObject(self.clearTimeout, forKeyedSubscript: "clearTimeout" as (NSCopying & NSObjectProtocol))
            jsContext.setObject(self.setInterval, forKeyedSubscript: "setInterval" as (NSCopying & NSObjectProtocol))
            jsContext.setObject(self.clearInterval, forKeyedSubscript: "clearInterval" as (NSCopying & NSObjectProtocol))
        }
    }
    
    
    
    //
    // JS Methods
    //
    
    // Timeout
    public var setTimeout: (@convention(block) (JSValue, Double) -> UInt)!
    public var clearTimeout: (@convention(block) (UInt) -> Void)!
    
    // Interval
    public var setInterval: (@convention(block) (JSValue, Double) -> UInt)!
    public var clearInterval: (@convention(block) (UInt) -> Void)!
    
    
    
    //
    // Internals
    //
    
    internal var timers = [UInt: Timer]()
    internal var prevTimerId: UInt = 0
    
    fileprivate struct TimerData {
        var id: UInt
        var callbackManagedValue: JSManagedValue
        var delayMS: Double
        var repeats: Bool
    }
    
    internal  func createTimer(callback: JSValue, delay: Double, repeats: Bool) -> UInt {
        let callbackManagedValue = JSManagedValue(value: callback)!
        let timerId = prevTimerId + 1
        
       //workerQueue?.async {
            self.prevTimerId = timerId
//            let timer = Timer.scheduledTimer(
//                timeInterval: delay/1000.0,
//                target: self,
//                selector: #selector(self.fireTimer(timer:)),
//                userInfo: TimerData(id: timerId, callbackManagedValue: callbackManagedValue, delayMS: delay, repeats: repeats),
//                repeats: repeats
//            )
            /*
            // NOTE: the following implementation requires iOS 10, so we'll switch to it eventually
            let timer = Timer.scheduledTimer(withTimeInterval: delay/1000.0, repeats: repeats) { timer in
                let callback = callbackManagedValue.value
                guard callback?.call(withArguments: []) != nil else {
                    // INFO: callback no-longer exists, or is not a function
                    timer.invalidate()
                    timers.removeValue(forKey: timerId)
                    return
                }
                if !repeats {
                    timers.removeValue(forKey: timerId)
                }
            }
            */
            
//           self.jsQueue?.async { callback.context.virtualMachine.addManagedReference(callbackManagedValue, withOwner: timer)
//           }
            //self.timers[timerId] = timer
            
            self.workerQueue?.asyncAfter(deadline: .now() + delay/1000.0, execute: {
                self.fire(
                    timer: TimerData(id: timerId, callbackManagedValue: callbackManagedValue, delayMS: delay, repeats: repeats)
                )
            })
      //  }
        //RunLoop.current.add(timer, forMode: .defaultRunLoopMode)
        return timerId
    }
    
    fileprivate func fire(timer: TimerData) {
        let userInfo = timer //.userInfo as! TimerData
        guard let q = jsQueue else {
            return
        }
        q.async {
            if let callback = userInfo.callbackManagedValue.value {
                if callback.isNull || callback.isUndefined {
                    //timer.invalidate()
                    //self.timers.removeValue(forKey: userInfo.id)
                }
                let _ = callback.call(withArguments: [])//!= nil else {
                    // INFO: callback no-longer exists, or is not a function
                    //timer.invalidate()
                    //self.timers.removeValue(forKey: userInfo.id)
//                    return
//                }
                if !userInfo.repeats {
                    //self.timers.removeValue(forKey: userInfo.id)
                } else {
                    self.workerQueue?.asyncAfter(
                        deadline: .now() + timer.delayMS/1000.0,
                        execute: {
                           self.fire(
                            timer: timer
                           )
                    })
                }
            }
        }
        
    }
    
    @objc internal  func fireTimer(timer: Timer) {
        let userInfo = timer.userInfo as! TimerData
        guard let q = jsQueue else {
            return
        }
        q.async {
            if let callback = userInfo.callbackManagedValue.value {
                if callback.isNull || callback.isUndefined {
                    timer.invalidate()
                    self.timers.removeValue(forKey: userInfo.id)
                }
                guard callback.call(withArguments: []) != nil else {
                    // INFO: callback no-longer exists, or is not a function
                    timer.invalidate()
                    self.timers.removeValue(forKey: userInfo.id)
                    return
                }
                if !userInfo.repeats {
                    self.timers.removeValue(forKey: userInfo.id)
                }
            }
        }
        
    }
    
    internal  func invalidateTimer(_ identifier: UInt) {
        guard let q = jsQueue else {
           return
       }
       q.async {
            if let timer = self.timers.removeValue(forKey: identifier) {
                let userInfo = timer.userInfo as! TimerData
                let callbackManagedValue = userInfo.callbackManagedValue
                let callback = callbackManagedValue.value
                callback?.context.virtualMachine.removeManagedReference(callbackManagedValue, withOwner: timer)
                
                timer.invalidate()
            }
        }
    }
    
    
    
}
