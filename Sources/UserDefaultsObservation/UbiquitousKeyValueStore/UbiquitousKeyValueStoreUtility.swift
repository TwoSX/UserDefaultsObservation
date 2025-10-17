//
//  File.swift
//  
//
//  Created by Taylor Geisse on 3/13/24.
//

import Foundation

public class UbiquitousKeyValueStoreUtility: @unchecked Sendable {
    // MARK: - Typealiases
    public typealias UbiquitousKVSKey              = String
    public typealias UbiquitousKVSReasonKey        = Int
    public typealias UbiquitousKVSUpdateCallback   = (UbiquitousKVSReasonKey) throws -> Void
    
    private let queue = DispatchQueue(label: "com.userdefaultsobservation.ubiquitouskeyvaluestore")
    private var updateCallbacks: [UbiquitousKVSKey: UbiquitousKVSUpdateCallback] = [:]
    private var cachedUpdates: [UbiquitousKVSKey: [UbiquitousKVSReasonKey]] = [:]
    private var observerAdded = false
    
    // Make this a singleton
    static public let shared = UbiquitousKeyValueStoreUtility()
    private init() {
        addDidChangeExternallyNotificationObserver()
        synchronize()
    }
    
    // MARK: - Notification Registration
    internal func addDidChangeExternallyNotificationObserver() {
        if observerAdded { return }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(ubiquitousKeyValueStoreDidChange(_:)),
                                               name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: NSUbiquitousKeyValueStore.default)
        observerAdded = true
    }
    
    public func synchronize() {
        if NSUbiquitousKeyValueStore.default.synchronize() == false {
            fatalError("This app was not built with the proper entitlement requests.")
        }
    }
    
    // MARK: - Update Callback Registration
    public func registerUpdateCallback(forKey key: String, callback: @escaping UbiquitousKVSUpdateCallback) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.updateCallbacks[key] = callback
            self.processCache(forKey: key)
        }
    }
    
    private func processCache(forKey key: String) {
        if cachedUpdates[key] == nil { return }
        cachedUpdates[key]?.forEach { executeUpdateCallback(forKey: key, reason: $0) }
        cachedUpdates[key] = nil
    }
    
    // MARK: - External Notification
    @objc func ubiquitousKeyValueStoreDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        guard let reasonForChange = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { return }
        guard let keys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else { return }
        
        queue.async {
            keys.forEach { self.executeUpdateCallback(forKey: $0, reason: reasonForChange) }
        }
    }
    
    private func executeUpdateCallback(forKey key: UbiquitousKVSKey, reason: UbiquitousKVSReasonKey) {
        guard let updateCallback = updateCallbacks[key] else {
            addKeyReasonToCache(forKey: key, reason: reason)
            return
        }
        
        do {
            try updateCallback(reason)
        } catch {
            addKeyReasonToCache(forKey: key, reason: reason)
        }
    }
    
    private func addKeyReasonToCache(forKey key: UbiquitousKVSKey, reason: UbiquitousKVSReasonKey) {
        cachedUpdates[key, default: []].append(reason)
    }
}
