//
//  DatabaseManager.swift
//  Refraktions
//
//  Created by Jason Snell on 3/7/16.
//  Copyright © 2016 Jason J. Snell. All rights reserved.
//

import UIKit

public class XvDatabase {
    
    //singleton code
    public static let sharedInstance = XvDatabase()
    fileprivate init() {}
    
    
    //MARK:- CONSTANTS -
    
    //MARK: MODE TYPES
    public let MODE_OFF = "OFF" // general, no collection
    public var MODE_SESSION = "SESSION" //session data only
    public var MODE_PERFORMANCE = "PERFORMANCE" //all data, session and instrument
    
    //MARK: FILE NAMES
    fileprivate var GET_MODE_FILE:String = "get_mode.php"
    fileprivate var PUSH_SESSION_DATA_FILE:String = "push_session_data.php"
    fileprivate var PUSH_PERFORMANCE_DATA_FILE:String = "push_performance_data.php"
    fileprivate var PULL_SESSION_DATA_FILE = "pull_session_data.php"
    fileprivate var PULL_PERFORMANCE_DATA_FILE = "pull_performance_data.php"

    //MARK: CALLBACK TYPES
    fileprivate var CALLBACK_AS_JSON:String = "callbackJSON"
    fileprivate var CALLBACK_AS_STRING:String = "callbackString"
    
    //MARK: TOUCH
    fileprivate let TOUCH_POINTS_PER_PACKET:Int = 5
    
    //MARK:- VARS -
    
    //MARK: APP & DEVICE DATA
    fileprivate var mode:String = ""
    fileprivate var rootUrl:String = ""
    fileprivate var appID:String = ""
    fileprivate var appVersion:String = ""
    fileprivate var deviceID:String = ""
    
    //MARK: PERFORMANCE DATA
    fileprivate var performanceData:[String] = []
    
    
    fileprivate var debug:Bool = false
    
    
    public func setup(rootUrl:String, appID:String, appVersion:String) {
        
        //record vars
        self.rootUrl = rootUrl
        self.appID = appID
        self.appVersion = appVersion
        
        //start process
        syncWithDB()
    }
    
    //MARK:-
    //MARK: ACCESSORS
    
    internal func getMode() -> String {
        return mode
    }
    
    //MARK:- USER APP METHODS -
    
    //MARK: 1. general init
    fileprivate func syncWithDB(){
        
        //get device ID to be able to see how many unique users are particpating in group shows
        deviceID = UIDevice.current.identifierForVendor!.uuidString
        
        //grab the mode from the server and reset app mode
        syncMode()
        
    }
    
    //MARK: 2 sync mode with server
    //get mode from server and set it locally
    fileprivate func syncMode(){
        
        pullData(rootUrl + GET_MODE_FILE, callbackAs: CALLBACK_AS_STRING) {
            
            (result, error) in
            
            if result != nil {
                
                switch result! as! String {
                    
                case self.MODE_PERFORMANCE:
                    self.mode = self.MODE_PERFORMANCE
                    
                case self.MODE_SESSION:
                    self.mode = self.MODE_SESSION
                    
                default:
                    self.mode = self.MODE_OFF
                    
                }
                
                if (self.debug){
                    print("DATABASE: mode sync'd = \(self.mode)")
                }
                
                if (self.mode == self.MODE_SESSION || self.mode == self.MODE_PERFORMANCE){
                    self.pushSessionData()
                }
                
            }
            
        }
    }
    
    //MARK: 3. push session data
    fileprivate func pushSessionData(){
        
        //create POST string of session data
        let dataString:String = "AppID=" + appID + "&AppVersion=" + appVersion + "&DeviceID=" + deviceID
        
        if let data:Data = dataString.data(using: String.Encoding.utf8) {
            
            //send to function that handles server uploads
            pushData(data, url: rootUrl + PUSH_SESSION_DATA_FILE){
                
                (result, error) in
                
                if (self.debug){
                    if result != nil {
                        print("DATABASE: PUSH session result = \(result!)")
                        
                    } else {
                        print("DATABASE: PUSH session error")
                    }
                }
                
            }

        } else {
            print("DATABASE: Error getting data string during pushSessionData")
        }
        
        
    }
    
    
    
    
    
    //MARK: 4. Called from UserDataManager, sending touch data
    //when at threshold, push to server
    //note: this is the only publicly accessible function
    
    public func record(instrument:Int, key:Int){
        
        if (mode == MODE_PERFORMANCE){
            
            //create string with X Y coordinate data
            let touchPosition:String = "X" + String(instrument) + "Y" + String(key)
            
            //add to array
            performanceData.append(touchPosition)
            
            //when we hit the max...
            if (performanceData.count >= TOUCH_POINTS_PER_PACKET){
                
                //... push to database manager
                push(performanceData: performanceData)
                
                //and reset array
                performanceData = []
            }
            
        }
        
    }
    
    //transmits instrument note counts to the database on the server
    fileprivate func push(performanceData:[String]){
       
        //create a string of the values with hyphens in between
        let dataString:String = performanceData.joined(separator: "-")
        
        //create POST string of data
        if let data:Data = String("UserTouchData=" + dataString).data(using: String.Encoding.utf8) {
            
            //send to function that handles server uploads
            pushData(data, url: rootUrl + PUSH_PERFORMANCE_DATA_FILE){
                
                (result, error) in
                
                if (self.debug){
                    if result != nil {
                        print("DATABASE: PUSH performance result = \(result!)")
                    } else {
                        print("DATABASE: PUSH performance error")
                    }
                }
                
            }

        } else {
            print("DATABASE: Error getting data string during push performanceData")
        }
        
        
    }
    
    //MARK:- MASTER APP METHODS -
    
    //MARK: pull session data from server
    //used by master app to retrieve data from satelite apps
    fileprivate func pullSessionData(){
        
        pullData(rootUrl + PULL_SESSION_DATA_FILE, callbackAs: CALLBACK_AS_JSON) {
            
            (result, error) in
            
            if (self.debug){
                print(result!)
            }
            
        }
        
    }
    
    //MARK: pull performance data from server
    //used by master app to retrieve data from satelite apps
    fileprivate func pullPerformanceData(){
        
        pullData(rootUrl + PULL_PERFORMANCE_DATA_FILE, callbackAs: CALLBACK_AS_JSON) {
            
            (result, error) in
            
            if (self.debug){
                print(result!)
            }
            
        }
        
    }
    
    
    
    //MARK:-
    //MARK: UTILS
    
    //MARK: PULL
    fileprivate func pullData(_ url:String, callbackAs:String, completion: @escaping (_ result: AnyObject?, _ error: NSError?)->()) {
        
        //load url into session
        let url:URL = URL(string: url)!
        let session = URLSession.shared
        
        //make POST request
        var request:URLRequest = URLRequest(url: url)
        
        request.httpMethod = "POST"
        request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringCacheData
        
        if (debug){
            print(" ")
            print("DATABASE: PULL")
        }
        
        //task with response handler
        let task:URLSessionDataTask = session.dataTask(with: request, completionHandler: {
            
            (data, response, error) in
            
            //error handling
            guard let _:Data = data, let _:URLResponse = response  , error == nil else {
                if (self.debug){
                    print("DATABASE: PULL Error loading data from server")
                }
                completion(nil, error as NSError?)
                return
            }
            
            //return data as a simple string
            if (callbackAs == self.CALLBACK_AS_STRING){
                
                let dataString = NSString(data: data!, encoding: String.Encoding.utf8.rawValue)
                
                //send string to completion handler
                completion(dataString, nil)
                
                //or return data as a parsed JSON
            } else if (callbackAs == self.CALLBACK_AS_JSON){
                
                //parse data
                do {
                    
                    let json:Any = try JSONSerialization.jsonObject(with: data!, options: .allowFragments)
                    
                    //send json to completion handler
                    completion(json as AnyObject?, nil)
                    
                    // error catching
                } catch {
                    if (self.debug){
                        print("DATABASE: PULL Error parsing JSON: \(error)")
                    }
                    
                }
                
            }
            
        })
        
        //start task
        task.resume()
        
    }
    
    //MARK: PUSH
    fileprivate func pushData(_ data:Data, url:String, completion: @escaping (_ result: AnyObject?, _ error: NSError?)->()) {
        
        //load url into session
        let nsURL:URL = URL(string: url)!
        let session = URLSession.shared
        
        //make POST request
        let request = NSMutableURLRequest(url: nsURL)
        request.httpMethod = "POST"
        request.cachePolicy = NSURLRequest.CachePolicy.reloadIgnoringCacheData
        
        if (debug){
            print(" ")
            print("DATABASE: PUSH")
        }
        
        //task with response handler
        let task = session.uploadTask(with: request as URLRequest, from: data, completionHandler: {
            
            (data, response, error) in
            
            guard let _:Data = data, let _:URLResponse = response  , error == nil else {
                
                //error
                if (self.debug){
                    print("DATABASE: PUSH Error sending data to server")
                }
                completion(nil, error as NSError?)
                return
            }
            
            
            //print data
            let dataString = NSString(data: data!, encoding: String.Encoding.utf8.rawValue)
            
            if (self.debug){
                print("DATABASE: SEND data response: \(String(describing: dataString))")
            }
            
            completion(dataString, nil)
            
            
            
        }
        )
        
        task.resume()
    }
    
}

